#!/bin/sh
# Adapts the upstream dashboard's init_react_envs.sh and nginx config to
# nginx-unprivileged. Runs at build time, not at runtime.
set -eu

conf=/etc/nginx/conf.d/default.conf
init=/docker-entrypoint.d/40-init-react-envs.sh

# nginx-unprivileged runs as uid 101 and cannot bind privileged ports
sed -i 's/listen 80 default_server;/listen 8080 default_server;/' "$conf"
sed -i 's/listen \[::\]:80 default_server;/listen [::]:8080 default_server;/' "$conf"

# It also reads from conf.d, while the script patches the CSP header in http.d
sed -i 's|/etc/nginx/http.d/default.conf|'"$conf"'|g' "$init"

# The script ends with a mandatory `nginx -s reload` loop that exits 1 on failure.
# Under supervisord nginx is already running by then, but the nginx-unprivileged
# entrypoint runs docker-entrypoint.d/* *before* starting nginx, so the reload can
# never succeed. Drop everything from that block onwards.
sed -i '/^# Reload nginx so the patched CSP header takes effect\./,$d' "$init"

chmod +x "$init"

# Sanity checks - fail the build rather than ship something broken
grep -q 'listen 8080 default_server;' "$conf"
! grep -q 'nginx -s reload' "$init"
grep -q "$conf" "$init"
