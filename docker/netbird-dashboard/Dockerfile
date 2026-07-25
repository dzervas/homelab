ARG VERSION=v2.90.7

# The upstream image runs supervisord as root, which spawns an nginx master that
# binds :80 and chowns its temp dirs - needing NET_BIND_SERVICE, CHOWN, SETUID and
# SETGID. Only the built SPA and the env templating script are actually useful, so
# both are lifted onto nginx-unprivileged, which needs no capabilities at all.
FROM netbirdio/dashboard:${VERSION} AS src

FROM nginxinc/nginx-unprivileged:1.29-alpine

USER root

# init_react_envs.sh is bash, alpine only ships ash
RUN apk add --no-cache bash

# The html dir already exists in the base image owned by root, and --chown only
# applies to the copied files - the script writes new files into it, so the
# directory itself has to be chowned separately
COPY --from=src --chown=101:101 /usr/share/nginx/html /usr/share/nginx/html
RUN chown -R 101:101 /usr/share/nginx/html
COPY --from=src --chown=101:101 /etc/nginx/http.d/default.conf /etc/nginx/conf.d/default.conf
COPY --from=src /usr/local/init_react_envs.sh /docker-entrypoint.d/40-init-react-envs.sh
COPY patch-init.sh /tmp/patch-init.sh

# The CSP sed rewrites default.conf in place, which needs write on its directory
RUN /tmp/patch-init.sh && rm /tmp/patch-init.sh && chown -R 101:101 /etc/nginx/conf.d

USER 101

EXPOSE 8080
