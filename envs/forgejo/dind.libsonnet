// Proven in envs/forgejo-dind-canary on AMD64 and ARM64; shared bootstrap, not a production dependency on that env
{
  // Last Docker 29 patch with runc 1.3.5; 29.6+ mask mounts need unsupported tmpfs options (gVisor#13670)
  // gVisor release-20260714.0 adds nr_blocks/nr_inodes and removes this blocker; retest before repinning
  // Archived, not LTS/maintained: this compatibility pin does not receive subsequent security fixes
  version: '29.5.3',
  socket: 'unix:///run/dind/docker.sock',
  annotations: {
    // Gofer-backed sockets are not unified across container mount namespaces
    'dev.gvisor.spec.mount.dind-socket.type': 'tmpfs',
    'dev.gvisor.spec.mount.dind-socket.share': 'pod',
    'dev.gvisor.spec.mount.dind-socket.options': 'rw,size=16m',
  },
  startupScript:: |||
    #!/bin/sh
    set -eu

    # POSIX adaptation of https://github.com/google/gvisor/blob/master/images/basic/docker/start-dockerd.sh
    interface=$(ip -4 route show default | awk '{for (i=1; i<NF; i++) if ($i == "dev") {print $(i+1); exit}}')
    : "${interface:?No default IPv4 interface}"
    address=$(ip -4 addr show dev "$interface" | awk '/inet / {split($2, parts, "/"); print parts[1]; exit}')
    : "${address:?No sandbox IPv4 address}"
    # gVisor does not expose ordinary interfaces in sysfs; read MTU through netlink
    mtu=$(ip link show dev "$interface" | awk '{for (i=1; i<NF; i++) if ($i == "mtu") {print $(i+1); exit}}')
    : "${mtu:?No sandbox interface MTU}"

    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables-legacy -t nat -A POSTROUTING -o "$interface" -j SNAT --to-source "$address" -p tcp
    iptables-legacy -t nat -A POSTROUTING -o "$interface" -j SNAT --to-source "$address" -p udp

    # Vfs disk is a bounded correctness baseline, not a production performance approval
    # Literal dockerd avoids the entrypoint's unauthenticated TCP listener; no managed port publishing
    exec dockerd-entrypoint.sh dockerd \
      --host="$DOCKER_HOST" --group=1000 \
      --iptables=false --ip6tables=false --mtu="$mtu" \
      --feature containerd-snapshotter=false --storage-driver=vfs
  |||,
}
