{
  config,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    cilium-cli # cilium
  ];

  boot = {
    # Required by longhorn RWX volumes, which are NFS-backed via
    # share-manager. Loads the nfs/nfs4 kernel modules and installs the
    # nfs-utils mount.nfs helper, without which kubelet's mount fails with
    # "NFS: mount program didn't pass remote address".
    supportedFilesystems = [ "nfs" ];

    kernelParams = [
      # Required by longhorn
      "hugepagesz=2M"
      "hugepages=1024"
    ];
    kernelModules = [
      # Required by longhorn
      "nvme_tcp"
      "vfio_pci"
      "uio_pci_generic"
      "dm_crypt"
      "nfs"

      # Required by linstor
      "nvme_rdma"
      "dm_cache"
      "dm_writecache"
      "dm_snapshot"
      "bcache"

      # Maybe good for Calico
      "xt_bpf"
      "ipt_ipvs"
      "ipt_set"
      "vfio-pci"
      "ip6_tables"

      # Kube proxy stuff
      "nf_conntrack"
      "nf_nat"
      "iptable_nat"
      "xt_MASQUERADE"
    ];

    kernel.sysctl = {
      # Enable hugepages (for openEBS)
      "vm.nr_hugepages" = 1024;

      # ingress-nginx performance tuning
      # https://www.f5.com/company/blog/nginx/tuning-nginx
      "net.core.somaxconn" = 32768; # Maximum number of connections in the listen queue
      # This is not valid in nix:
      # "net.ipv4.ip_local_port_range" = "1024 65000"; # Range of ports for ephemeral (client) connections

      # Linstor
      "net.core.rmem_max" = 1048576;

      # Cilium's DNS proxy redirect (fwmark 0x200 -> table 2004 "local default dev lo")
      # makes pod DNS queries (lxc*) and CoreDNS replies (wg0) martian when
      # src_valid_mark=1. cilium/cilium#46284. Only on those interfaces: systemd's
      # udev rule applies per-interface keys to new pod veths as they appear
      "net.ipv4.conf.lxc*.accept_local" = 1;
      "net.ipv4.conf.wg0.accept_local" = 1;

      # if applicable:
      # "net.ipv4.conf.flannel.1.rp_filter" = 0;
      # "net.ipv4.conf.cali*.rp_filter" = 0;
    };
  };

  # Longhorn shenanigans
  # https://github.com/longhorn/longhorn/issues/2166#issuecomment-2994323945
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };
  systemd.tmpfiles.rules = [
    # Create a symbolic link /usr/bin/mount -> /run/current-system/sw/bin/mount
    "L /usr/bin/mount - - - - /run/current-system/sw/bin/mount"
    # Longhorn runs iscsiadm by PATH in iscsid's mount namespace, and caches
    # iscsid's PID per engine, so iscsid must not be restarted under it.
    # Resolved at exec time, so it follows the current system without restarts
    "L /usr/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
  ];
}
