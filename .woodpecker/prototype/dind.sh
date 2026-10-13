#!/bin/sh
set -eu

: "${CI_WORKSPACE:?}" "${PROTOTYPE_ARCH:?}"
case "$PROTOTYPE_ARCH" in amd64|arm64) ;; *) exit 1 ;; esac

# Admission mounts the shared Forgejo SNAT/MTU/VFS baseline at this path
# Its command omits literal dockerd/--host so Docker's stock entrypoint creates TLS listeners
umask 077
export DOCKER_TLS_CERTDIR="$CI_WORKSPACE/.prototype-private-$PROTOTYPE_ARCH"
export DOCKER_TLS_SAN="DNS:prototype-dind-$PROTOTYPE_ARCH"
mkdir -p "$DOCKER_TLS_CERTDIR"
exec sh /prototype/start-dind.sh
