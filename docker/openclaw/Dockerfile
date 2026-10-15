# syntax=docker/dockerfile:1

# Follow the current official browser release on each CI rebuild.
# For local builds, use --pull --no-cache to refresh the base and CLI download.
FROM ghcr.io/openclaw/openclaw:latest-browser

USER root

# The browser base already supplies Chromium's shared libraries and Xvfb.
# Add emoji/CJK coverage, not proprietary Windows/macOS fonts.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      fonts-liberation fonts-noto-color-emoji fonts-freefont-ttf \
      fonts-unifont fonts-ipafont-gothic fonts-wqy-zenhei \
      fonts-tlwg-loma-otf fonts-urw-base35 \
    && rm -rf /var/lib/apt/lists/*

# Transparently replace playwright-core, including plugin-local pnpm links.
# Derive Patchright's exact version from the base image; missing releases or
# changes to OpenClaw's compiled Runtime.enable patch point fail the build.
COPY install-patchright.mjs /tmp/install-patchright.mjs
RUN node /tmp/install-patchright.mjs \
    && node /app/node_modules/playwright-core/cli.js install chromium \
    && node -e 'const fs = require("node:fs"); const { chromium } = require("playwright-core"); fs.accessSync(chromium.executablePath(), fs.constants.X_OK);' \
    && chown -R node:node "$PLAYWRIGHT_BROWSERS_PATH" \
    && rm -rf /tmp/install-patchright.mjs /root/.npm

# Latest stable 1Password CLI, as in docker/hermes; no credentials.
# dpkg detects the native architecture even when Kaniko omits TARGETARCH.
RUN arch=$(dpkg --print-architecture) \
    && curl -fsSL -o /tmp/op.deb \
      "https://downloads.1password.com/linux/debian/${arch}/stable/1password-cli-${arch}-latest.deb" \
    && dpkg -i /tmp/op.deb \
    && rm /tmp/op.deb \
    && op --version

# op's daemon socket and config must be writable without root. Authentication
# (e.g. OP_SERVICE_ACCOUNT_TOKEN) is supplied only at runtime.
RUN test "$(id -u node)" = 1000 \
    && install -d -o node -g node -m 0700 \
      /home/node/.config/op /home/node/.cache /tmp/openclaw-runtime
ENV HOME=/home/node \
    XDG_RUNTIME_DIR=/tmp/openclaw-runtime

# Use the bundled Chromium discovered via PLAYWRIGHT_BROWSERS_PATH; no sidecar.
# Gateway launches it directly, so Patchright's launch-argument changes do not
# apply: deployment should set extraArgs=["--disable-blink-features=AutomationControlled"].
# Deployment owns headless/noSandbox (gVisor), profile persistence and secrets.
# Patchright intentionally disables console capture; browser-panel compatibility
# and anti-detection effectiveness still need a full image/runtime test.
# Retain the official ENTRYPOINT, CMD and healthcheck.
USER 1000:1000
