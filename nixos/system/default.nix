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

    # Raise the maximum number of open files
    "fs.inotify.max_queued_events" = 32768;
    "fs.inotify.max_user_instances" = 512;
    "fs.inotify.max_user_watches" = 524288;
  };

  time.timeZone = "Europe/Athens";

  programs.nix-ld.enable = true;
  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "25.05";

  # Remove some default packages that come with nix
  environment.defaultPackages = [];
}
