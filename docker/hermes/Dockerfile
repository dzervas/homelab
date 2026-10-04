# syntax=docker/dockerfile:1.7

FROM nousresearch/hermes-agent:latest

USER root

# 1Password CLI: backs the credential vault (browser autofill on the right
# origin). Picked up from PATH, authenticated by OP_SERVICE_ACCOUNT_TOKEN
# kaniko doesn't set TARGETARCH; ask the build's own userland instead
RUN arch=$(dpkg --print-architecture) \
    && curl -fsSL -o /tmp/op.deb \
      "https://downloads.1password.com/linux/debian/${arch}/stable/1password-cli-${arch}-latest.deb" \
    && dpkg -i /tmp/op.deb \
    && rm /tmp/op.deb \
    && op --version

# stage2-hook.sh (set -eu) writes AGENT_BROWSER_EXECUTABLE_PATH into s6's
# envdir even without /init, and a rootless bootstrap can't create it in /run
RUN install -d -o hermes -g hermes /run/s6/container_environment

# The base image bakes XDG_RUNTIME_DIR in root-owned, and the rootless bootstrap
# can only create or chown it, so op can't put its daemon socket there
RUN install -d -o hermes -g hermes -m 700 /tmp/hermes-runtime

# Rootless: the image's own hermes user is the one non-root UID the bootstrap
# accepts (docker/stage2-hook.sh). It only works when the entrypoint is not
# PID 1, which makes entrypoint-dispatch.sh skip s6-overlay's /init (that
# needs root) and run the bootstrap + command directly. In Kubernetes that's
# shareProcessNamespace: true
USER 10000:10000
