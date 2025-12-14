_: {
  imports = [
    ./bash.nix
    ./boot.nix
    ./disk.nix
    ./network.nix
    ./nix.nix
    ./options.nix
  ];

  services = {
    fwupd.enable = true;
    openssh.enable = true;
    cron.enable = true;
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIB9rcx6pJF2ZEJsB5oFWF0E7LKOL5HQlA2uPdvDdafq"
  ];

  networking.enableIPv6 = false;

  boot.kernel.sysctl = {
    # IPv4 forwarding - needed for networking
    "net.ipv4.ip_forward" = 1;
    # Cause who needs IPv6
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;

    # Disable ICMP redirects, could be used to alter the routing tables of other nodes
    # https://www.tenable.com/audits/items/CIS_Debian_Linux_7_v1.0.0_L1.audit:c120d5af44f5fbed18c683f4c56f12e2
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;

    # Do nothing about obviously wrong (e.g. crazy saddr) packets, drop them
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;

    # Strict reverse path filtering
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;

    # Raise the maximum number of open files
    "fs.inotify.max_queued_events" = 32768;
    "fs.inotify.max_user_instances" = 512;
    "fs.inotify.max_user_watches" = 524288;
  };
  # LVM stuff
  boot.kernelModules = [ "dm-thin-pool" "dm-snapshot" ];

  time.timeZone = "Europe/Athens";

  programs.nix-ld.enable = true;
  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "25.05";

  # Remove some default packages that come with nix
  environment.defaultPackages = [];
}
