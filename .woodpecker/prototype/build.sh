#!/busybox/sh
set -eu

: "${CI_WORKSPACE:?}" "${PROTOTYPE_ARCH:?}" "${PROTOTYPE_BUILD:?}"
case "$PROTOTYPE_ARCH" in amd64|arm64) ;; *) exit 1 ;; esac
case "$PROTOTYPE_BUILD" in cold|warm) ;; *) exit 1 ;; esac
out="$CI_WORKSPACE/.prototype-results-$PROTOTYPE_ARCH"
mkdir -p "$out" /cache/layers
log="$out/$PROTOTYPE_BUILD.log"

# Ordinary executor commands: no plugin registry credentials or image publication
# Cache destinations append :<key>; keeping the parent under /cache is essential
# Separate Pods avoid unpacking a base image over the previous invocation's rootfs
if /kaniko/executor \
  --force \
  --context="$CI_WORKSPACE/.woodpecker/prototype/context" \
  --dockerfile="$CI_WORKSPACE/.woodpecker/prototype/context/Dockerfile" \
  --destination="woodpecker-prototype:$PROTOTYPE_ARCH" \
  --cache=true --cache-repo=oci:/cache/layers \
  --no-push \
  --tar-path="$out/$PROTOTYPE_BUILD.tar" \
  --oci-layout-path="$out/$PROTOTYPE_BUILD-oci" \
  > "$log" 2>&1; then
  cat "$log"
else
  cat "$log"
  exit 1
fi

test -s "$out/$PROTOTYPE_BUILD.tar"
test -s "$out/$PROTOTYPE_BUILD-oci/index.json"
if [ "$PROTOTYPE_BUILD" = warm ]; then
  # Match the marked RUN itself, not an unrelated base/COPY cache message
  grep -F 'Using caching version of cmd: RUN uname -m > /native-arch' "$log"
fi
