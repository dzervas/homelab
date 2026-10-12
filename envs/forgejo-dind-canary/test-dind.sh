#!/bin/sh
set -eu

cleanup() {
  docker rm -f canary-service >/dev/null 2>&1 || true
  docker network rm canary >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker version
docker buildx version
[ "$(docker info --format '{{.Driver}}')" = vfs ]
[ "$(docker info --format '{{range .DriverStatus}}{{if eq (index . 0) "Extended file attributes"}}{{index . 1}}{{end}}{{end}}')" = best-effort ]
echo 'PASS: cross-container Docker socket and classic vfs storage with best-effort xattrs'

case "$EXPECTED_ARCH" in
  amd64) expected_machine=x86_64 ;;
  arm64) expected_machine=aarch64 ;;
  *) echo "Unsupported test architecture: $EXPECTED_ARCH" >&2; exit 1 ;;
esac
[ "$(docker run --rm "$TEST_IMAGE" uname -m)" = "$expected_machine" ]
echo "PASS: native nested container on $EXPECTED_ARCH"

printf 'workspace-ok\n' > /workspace/sentinel
[ "$(docker run --rm -v /workspace:/probe:ro "$TEST_IMAGE" cat /probe/sentinel)" = workspace-ok ]
echo 'PASS: workspace sharing between controller, daemon and nested container'

docker network create canary
# Alpine's BusyBox omits httpd; use a real HTTP server rather than assuming the applet exists
docker run -d --name canary-service --network canary --network-alias service \
  --entrypoint sh nginx:alpine \
  -ec 'echo service-ok > /usr/share/nginx/html/index.html; exec nginx -g "daemon off;"'
docker run --rm --network canary "$TEST_IMAGE" sh -ec '
  for attempt in 1 2 3 4 5; do
    response=$(wget -q -O - http://service) && [ "$response" = service-ok ] && exit 0
    sleep 1
  done
  exit 1
'
echo 'PASS: nested bridge networking, Docker DNS alias and HTTP service'

docker run --rm --network canary "$TEST_IMAGE" \
  sh -ec 'wget -q -O /dev/null https://example.com'
echo 'PASS: nested public DNS and HTTPS egress'

mkdir -p /tmp/context
cat > /tmp/context/Dockerfile <<EOF
FROM $TEST_IMAGE
RUN wget -q -O /dev/null https://example.com && echo build-ok > /proof
CMD ["cat", "/proof"]
EOF
docker buildx build --load --no-cache --progress=plain --tag gvisor-dind-proof /tmp/context
[ "$(docker run --rm gvisor-dind-proof)" = build-ok ]
echo 'PASS: BuildKit RUN with networking, image export and execution'
echo "GVISOR_DIND_CANARY_PASS $EXPECTED_ARCH"
