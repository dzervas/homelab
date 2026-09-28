# syntax=docker/dockerfile:1.7

FROM nousresearch/hermes-agent:latest

ARG TARGETARCH

USER root

# 1Password CLI: backs the credential vault (browser autofill on the right
# origin). Picked up from PATH, authenticated by OP_SERVICE_ACCOUNT_TOKEN
RUN curl -fsSL -o /tmp/op.deb \
      "https://downloads.1password.com/linux/debian/${TARGETARCH}/stable/1password-cli-${TARGETARCH}-latest.deb" \
    && dpkg -i /tmp/op.deb \
    && rm /tmp/op.deb \
    && op --version

# Rootless: the image's own hermes user is the one non-root UID the bootstrap
# accepts (docker/stage2-hook.sh). It only works when the entrypoint is not
# PID 1, which makes entrypoint-dispatch.sh skip s6-overlay's /init (that
# needs root) and run the bootstrap + command directly. In Kubernetes that's
# shareProcessNamespace: true
USER 10000:10000
