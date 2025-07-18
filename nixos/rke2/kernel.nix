{ pkgs, ... }: {
  boot = {
    # Required by openebs
    kernelModules = ["nvme_tcp" "dm_snapshot"];

    # Why not?
    kernelPackages = pkgs.linuxPackages_hardened;

    kernel.sysctl = {
      # Enable hugepages (for openEBS)
      "vm.nr_hugepages" = 1024;

      # ingress-nginx performance tuning
      # https://www.f5.com/company/blog/nginx/tuning-nginx
      "net.core.somaxconn" = 32768; # Maximum number of connections in the listen queue
      "net.ipv4.ip_local_port_range" = "1024 65000"; # Range of ports for ephemeral (client) connections
    };
  };
}
