#!/bin/sh
# sshd for Hermes' SSH terminal backend, logging in as `agent` (passwordless
# sudo). /home is the persistent volume.
#   /etc/workspace-ssh/authorized_keys: Hermes' public key (the only login)
#   GIT_CREDENTIALS: optional `https://user:token@host` lines for git
set -eu

home=/home/agent
# fsGroup leaves the volume root group-writable, which sshd's StrictModes rejects
chmod 755 /home

# Host keys live on the volume, root-only: Hermes pins them
# (StrictHostKeyChecking=accept-new), so regenerating them would break it
keys=/home/.sshd
install -d -m 700 "$keys"
for type in ed25519 rsa; do
  [ -f "$keys/ssh_host_${type}_key" ] || ssh-keygen -q -t "$type" -N '' -f "$keys/ssh_host_${type}_key"
done

if [ ! -d "$home" ]; then
  install -d -m 755 -o agent -g agent "$home"
  cp -r /etc/skel/. "$home"
  chown -R agent:agent "$home"
fi
install -d -m 700 -o agent -g agent "$home/.ssh"
install -m 600 -o agent -g agent /etc/workspace-ssh/authorized_keys "$home/.ssh/authorized_keys"

if [ -n "${GIT_CREDENTIALS:-}" ]; then
  printf '%s\n' "$GIT_CREDENTIALS" > "$home/.git-credentials"
  chown agent:agent "$home/.git-credentials"
  chmod 600 "$home/.git-credentials"
  runuser -u agent -- git config --global credential.helper store
fi

mkdir -p /run/sshd
exec /usr/sbin/sshd -D -e \
  -o HostKey="$keys/ssh_host_ed25519_key" \
  -o HostKey="$keys/ssh_host_rsa_key" \
  -o PermitRootLogin=no \
  -o AllowUsers=agent \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o UsePAM=no \
  -o X11Forwarding=no
