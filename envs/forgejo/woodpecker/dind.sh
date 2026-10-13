#!/bin/sh
set -eu

: "${CI_WORKSPACE:?}" "${DIND_SERVICE_NAME:?}"
# The backend's actual daemon Service name, not an architecture or pipeline alias
case "$DIND_SERVICE_NAME" in
  *[!a-z0-9-]*|-*|*-|'') echo 'Invalid DIND_SERVICE_NAME' >&2; exit 1 ;;
esac

# The workflow workspace shares private TLS certs with clients at this path/client
# Use this script as entrypoint, not commands/CI_SCRIPT: exec keeps Docker's tini PID 1
# Signal forwarding is tested offline; live Woodpecker teardown remains unverified
umask 077
export DOCKER_TLS_CERTDIR="$CI_WORKSPACE/.woodpecker-dind/$DIND_SERVICE_NAME"
export DOCKER_TLS_SAN="DNS:$DIND_SERVICE_NAME"
mkdir -p "$DOCKER_TLS_CERTDIR"
exec sh /opt/woodpecker-dind/start-dind.sh
