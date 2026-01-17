FROM ghcr.io/cachix/devenv/devenv

WORKDIR /home/devenv/opencode
COPY --chown=1000:1000 . .

# Cache the build stuff
RUN devenv shell ls

ENV OPENCODE_CONFIG=/config/opencode.json
EXPOSE 4096/tcp
ENTRYPOINT [ "devenv", "shell" ]
CMD ["opencode", "web"]
