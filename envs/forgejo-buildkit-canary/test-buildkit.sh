#!/bin/sh
set -eu
cd /workspace

ctl() {
  buildctl --addr "$BUILDKIT_HOST" --tlscacert /tls/ca.crt \
    --tlscert /tls/tls.crt --tlskey /tls/tls.key --timeout 30 "$@"
}

# The very same stock image is used by server and probe; never print private keys
buildctl --version | tee buildkit-version.txt
grep -F 'v0.30.0' buildkit-version.txt
buildkit-runc --version | tee runc-version.txt
grep -F 'runc version 1.3.5' runc-version.txt

ready=false
for attempt in $(seq 1 60); do
  if ctl debug workers -v > workers.txt 2>ready-error.txt; then
    ready=true
    break
  fi
  sleep 2
done
[ "$ready" = true ] || { cat ready-error.txt >&2; exit 1; }
cat workers.txt
grep -E 'worker.executor: *oci' workers.txt
grep -E 'worker.snapshotter: *native' workers.txt
grep -E 'worker.network: *host' workers.txt
grep -F "linux/$EXPECTED_ARCH" workers.txt

# Positive mTLS succeeded first: a transport outage cannot masquerade as rejection
if buildctl --addr "$BUILDKIT_HOST" --tlscacert /tls/ca.crt --timeout 10 debug workers > unauth.txt 2>&1; then
  echo 'FAIL: server accepted a client without a certificate' >&2
  exit 1
fi
# gRPC may suppress the TLS alert; preserve the actual error for operator inspection
cat unauth.txt
grep -Ei 'tls|certificate|authentication|handshake' unauth.txt
ctl debug workers >/dev/null
echo 'MTLS_UNAUTHENTICATED_REJECTED'

mkdir -p context
cat > context/Dockerfile <<'EOF'
FROM alpine:3.23 AS probe
# Plain RUN, no insecure entitlement. Native host network is the virtual gVisor Pod
RUN set -eu; apk --no-cache --repositories-file /dev/null \
      --repository https://dl-cdn.alpinelinux.org/alpine/v3.23/main add curl ca-certificates; \
    curl --fail --silent --show-error https://example.com -o /https; test -s /https; \
    printf '{"machine":"%s","token":"%s","https":"verified"}\n' \
      "$(uname -m)" "$(cat /proc/sys/kernel/random/uuid)" > /proof.json
FROM scratch
COPY --from=probe /proof.json /proof.json
EOF

ctl build --progress plain --frontend dockerfile.v0 \
  --local context=context --local dockerfile=context \
  --opt "platform=linux/$EXPECTED_ARCH" \
  --output type=oci,dest=/workspace/probe.tar,compression=gzip \
  > build.log 2>&1 || { cat build.log >&2; exit 1; }
cat build.log
if [ "$PHASE" = warm ]; then
  # A cache hit on metadata or COPY alone does not prove that RUN survived restart
  run_step=$(awk '/RUN set -eu; apk/ {print $1; exit}' build.log)
  [ -n "$run_step" ]
  grep -F "$run_step CACHED" build.log
fi

# Examine the OCI export without Docker, host execution, new devices or privileges
mkdir oci
tar -xf probe.tar -C oci
[ -s oci/index.json ] && [ -s oci/oci-layout ]
grep -F '1.0.0' oci/oci-layout
# Verify every blob's actual digest (not just the JSON declarations)
for blob in oci/blobs/sha256/*; do
  [ "$(sha256sum "$blob" | awk '{print $1}')" = "${blob##*/}" ]
done
grep -l '"architecture"' oci/blobs/sha256/* > configs.txt
[ "$(wc -l < configs.txt)" -eq 1 ]
config=$(cat configs.txt)
grep -l '"config"' oci/blobs/sha256/* > manifests.txt
[ "$(wc -l < manifests.txt)" -eq 1 ]
manifest=$(cat manifests.txt)
grep -F "sha256:${manifest##*/}" oci/index.json
grep -F "sha256:${config##*/}" "$manifest"
grep -E '"architecture"[[:space:]]*:[[:space:]]*"'"$EXPECTED_ARCH"'"' "$config"
grep -E '"os"[[:space:]]*:[[:space:]]*"linux"' "$config"
# This scratch final image has exactly one gzip layer containing the native RUN proof
mkdir rootfs
layers=0
for blob in oci/blobs/sha256/*; do
  if tar -tzf "$blob" > layer.txt 2>/dev/null; then
    layers=$((layers + 1))
    grep -F "sha256:${blob##*/}" "$manifest"
    grep -x 'proof.json' layer.txt
    tar -xzf "$blob" -C rootfs
  fi
done
[ "$layers" -eq 1 ] && [ -s rootfs/proof.json ]
case "$EXPECTED_ARCH" in
  amd64) machine=x86_64 ;;
  arm64) machine=aarch64 ;;
  *) exit 1 ;;
esac
grep -F '"machine":"'"$machine"'"' rootfs/proof.json
grep -F '"https":"verified"' rootfs/proof.json
token=$(awk -F '"' '{print $8}' rootfs/proof.json)
[ "${#token}" -eq 36 ]
printf 'CACHE_TOKEN %s %s\n' "$EXPECTED_ARCH" "$token"
ctl du -v
printf 'BUILDKIT_CANARY_PASS %s %s (compare cold/warm token after server Pod restart)\n' "$EXPECTED_ARCH" "$PHASE"
