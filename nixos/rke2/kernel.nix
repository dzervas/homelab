{
  config,
  home-vpn-iface,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    drbd # linstor
  ];

  boot = {
    # Use newer version of the module
    extraModulePackages = with config.boot.kernelPackages; [ drbd ];
    extraModprobeConfig = "options drbd usermode_helper=disabled";

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

      # Required by linstor
      "drbd"
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

    # Why not?
    kernelPackages = pkgs.linuxPackages_hardened;

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

      # Allow hostport forwarding
      "net.ipv4.conf.${home-vpn-iface}.route_localnet" = 1;

      # Disable reverse path filtering for VPN interfaces
      "net.ipv4.conf.${home-vpn-iface}.rp_filter" = 2; # loose
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
  systemd.services.iscsid.serviceConfig = {
    PrivateMounts = "yes";
    BindPaths = "/run/current-system/sw/bin:/bin";
  };
  systemd.tmpfiles.rules = [
    # Create a symbolic link /usr/bin/mount -> /run/current-system/sw/bin/mount
    "L /usr/bin/mount - - - - /run/current-system/sw/bin/mount"
  ];
}
