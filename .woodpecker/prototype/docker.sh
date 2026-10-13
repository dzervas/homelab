#!/bin/sh
set -eu

: "${CI_WORKSPACE:?}" "${PROTOTYPE_ARCH:?}"
case "$PROTOTYPE_ARCH" in
  amd64) expected=x86_64 ;;
  arm64) expected=aarch64 ;;
  *) exit 1 ;;
esac
export DOCKER_HOST="tcp://prototype-dind-$PROTOTYPE_ARCH:2376"
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH="$CI_WORKSPACE/.prototype-private-$PROTOTYPE_ARCH/client"

# Bound both absent certificates and TLS/DNS/daemon startup failures to 180 seconds
if ! timeout 180 sh -c '
  until [ -s "$DOCKER_CERT_PATH/cert.pem" ] &&
    timeout 5 docker info >/dev/null 2>&1; do
    sleep 2
  done
'; then
  echo "TLS daemon did not become ready within 180 seconds: $DOCKER_HOST" >&2
  exit 1
fi

test "$(docker version --format '{{.Server.Version}}')" = 29.5.3
out="$CI_WORKSPACE/.prototype-results-$PROTOTYPE_ARCH"
image="woodpecker-prototype:$PROTOTYPE_ARCH"
docker load --input "$out/warm.tar"
test "$(docker image inspect --format '{{.Architecture}}' "$image")" = "$PROTOTYPE_ARCH"
test "$(docker run --rm "$image" cat /native-arch)" = "$expected"
test "$(docker run --rm "$image" uname -m)" = "$expected"

# Exercise an ordinary long-running container and exec, without port publishing
container="prototype-exec-$PROTOTYPE_ARCH"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT HUP INT TERM
docker run --detach --name "$container" "$image" sleep 300
test "$(docker exec "$container" uname -m)" = "$expected"
test "$(docker exec "$container" cat /native-arch)" = "$expected"
echo "Native $PROTOTYPE_ARCH TLS DinD, cached Kaniko tar load, run and exec passed"
