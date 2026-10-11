# syntax=docker/dockerfile:1
FROM debian:trixie-slim AS download

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Changes with every release, so a new release invalidates the cached download below.
ADD https://github.com/Microck/kagi-cli/releases/latest/download/release-notes.json /release-notes.json

# kaniko doesn't set TARGETARCH; ask the build's own userland instead
RUN set -eu; \
    arch=$(dpkg --print-architecture); \
    case "$arch" in \
      amd64) target=x86_64-unknown-linux-gnu ;; \
      arm64) target=aarch64-unknown-linux-gnu ;; \
      *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 1 ;; \
    esac; \
    latest=$(curl -fsSLo /dev/null -w '%{url_effective}' --retry 3 \
      https://github.com/Microck/kagi-cli/releases/latest); \
    tag=${latest##*/}; \
    curl -fsSL --retry 3 \
      "https://github.com/Microck/kagi-cli/releases/download/${tag}/kagi-${tag}-${target}" \
      -o /kagi; \
    chmod 0755 /kagi

FROM node:24-trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Refresh the cached install when npm publishes a new stable release
# Stable releases do not yet include the standalone binaries advertised on main
ADD https://registry.npmjs.org/supergateway/latest /tmp/supergateway-release.json
RUN npm install --global "supergateway@$(node -p 'require("/tmp/supergateway-release.json").version')" \
    && npm cache clean --force \
    && rm /tmp/supergateway-release.json \
    && supergateway --version

COPY --from=download /kagi /usr/local/bin/kagi

ENV HOME=/tmp/kagi \
    XDG_CONFIG_HOME=/tmp/kagi/config \
    XDG_CACHE_HOME=/tmp/kagi/cache \
    XDG_DATA_HOME=/tmp/kagi/data

USER 10001:10001
WORKDIR /tmp

# The child inherits KAGI_SESSION_TOKEN; clients receive tools, not the token
# For direct stdio clients, override the entrypoint with /usr/local/bin/kagi
EXPOSE 8000
ENTRYPOINT ["supergateway"]
CMD ["--stdio", "/usr/local/bin/kagi mcp", "--outputTransport", "streamableHttp", "--stateful", "--port", "8000", "--streamableHttpPath", "/mcp"]
