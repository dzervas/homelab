{ config, home-vpn-iface, pkgs, ... }: {
  environment.systemPackages = [ pkgs.drbd ];

  boot = {
    # Use newer version of the module
    extraModulePackages = with config.boot.kernelPackages; [ drbd ];
    extraModprobeConfig = "options drbd usermode_helper=disabled";

    kernelModules = [
      # Required by openebs
      "nvme_tcp" "dm_snapshot"

      # Required by linstor
      "drbd"
      "dm_cache" "dm_writecache"

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
      "net.core.rmem_max"	= 1048576;

      # Allow hostport forwarding
      "net.ipv4.conf.${home-vpn-iface}.route_localnet" = 1;

      # Disable reverse path filtering for VPN interfaces
      "net.ipv4.conf.${home-vpn-iface}.rp_filter" = 2; # loose
      # if applicable:
      # "net.ipv4.conf.flannel.1.rp_filter" = 0;
      # "net.ipv4.conf.cali*.rp_filter" = 0;
    };
  };
}
