{
	config,
  hostIndex,
  node-vpn-iface,
  node-vpn-prefix,
  ...
}: let
  listenAddress = "${node-vpn-prefix}.${hostIndex}";
in {
  services.prometheus.exporters = {
    node = {
      inherit listenAddress;
      enable = true;
      openFirewall = true;
      # Subsystems not present on these nodes; each still emits series by default.
      disabledCollectors = [
        "ipvs"  # Cilium replaces kube-proxy, so there are no IPVS tables
        "infiniband"
        "fibrechannel"
        "tapestats"
        "nfs"
        "nfsd"
        "xfs"
        "selinux"
      ];
      # Kubernetes nodes churn a veth per pod and a mount per container volume,
      # which multiplies the netdev/filesystem collectors into thousands of series.
      extraFlags = [
        "--collector.netdev.device-exclude=^(veth|lxc|cilium|cni|docker|flannel|kube|tap|dummy|virbr).*"
        # netclass is a separate collector with its own filter and ignores nothing by default.
        "--collector.netclass.ignored-devices=^(veth|lxc|cilium|cni|docker|flannel|kube|tap|dummy|virbr).*"
        "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run/containerd|var/lib/kubelet|var/lib/rancher|var/lib/longhorn|var/lib/docker)($|/)"
        # Longhorn attaches its volumes as sdb, sdc, ... and the letters are
        # reassigned as pods move, so each attachment mints new series. Allow-list
        # the real disks and LVM devices instead. Longhorn exports its own
        # longhorn_volume_* metrics for per-volume I/O.
        "--collector.diskstats.device-include=^(nvme[0-9]+n[0-9]+|sda|dm-[0-9]+)$"
      ];
      firewallRules = ''iifname ${node-vpn-iface} tcp dport ${toString config.services.prometheus.exporters.node.port} counter accept'';
    };
    smartctl = {
      inherit listenAddress;
      enable = true;
      openFirewall = true;
      firewallRules = ''iifname ${node-vpn-iface} tcp dport ${toString config.services.prometheus.exporters.smartctl.port} counter accept'';
    };
  };
}
