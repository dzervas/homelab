# syntax=docker/dockerfile:1.7

# Where Hermes' terminal, file tools and execute_code run (SSH backend). The
# agent logs in as `agent` with passwordless sudo, so it can install whatever
# it wants; the pod runs on gVisor and is the thing that's allowed to explode
FROM debian:latest

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server sudo \
      ca-certificates curl wget git jq ripgrep fd-find less vim-tiny tmux procps iproute2 dnsutils \
      unzip zip xz-utils file \
      build-essential pkg-config \
      python3 python3-venv python3-pip python3-dev pipx \
      nodejs npm \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# /home is the persistent volume, so the entrypoint recreates the home dir.
# Password `*` instead of useradd's locked `!`: without PAM, sshd refuses
# locked accounts even for key logins
RUN useradd -u 1000 -U -s /bin/bash -M -d /home/agent -p '*' agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent \
    && chmod 440 /etc/sudoers.d/agent

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
