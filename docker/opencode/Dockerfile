FROM ghcr.io/cachix/devenv/devenv

WORKDIR /home/devenv/opencode
COPY --chown=1000:1000 devenv.* .

# TODO: This is not enough
RUN devenv shell ls

ENV OPENCODE_CONFIG=/config/opencode.json
EXPOSE 4096/tcp
ENTRYPOINT [ "devenv", "shell" ]
CMD ["opencode", "web", "--port", "4096", "--hostname", "0.0.0.0", "--print-logs"]
