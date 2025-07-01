{ lib, pkgs, ... }: {
  imports = [
    ./bash.nix
    ./boot.nix
    ./disk.nix
    ./network.nix
    ./nix.nix
    ./options.nix
  ];

  environment.systemPackages = map lib.lowPrio (with pkgs; [
    curl
    git
  ]);

  services = {
    fwupd.enable = true;
    openssh.enable = true;
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIB9rcx6pJF2ZEJsB5oFWF0E7LKOL5HQlA2uPdvDdafq"
  ];

  boot.kernel.sysctl = {
    # IPv4 forwarding - needed for k3s
    "net.ipv4.ip_forward" = 1;
    # Raise the maximum number of open files
    "fs.inotify.max_queued_events" = 32768;
    "fs.inotify.max_user_instances" = 512;
    "fs.inotify.max_user_watches" = 524288;
    # Cause who needs IPv6
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
    # k3s hardening: https://docs.k3s.io/security/hardening-guide#ensure-protect-kernel-defaults-is-set
    "vm.panic_on_oom" = 0;
    "vm.overcommit_memory" = 1;
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
  };

  programs.nix-ld.enable = true;
  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "25.05";
}
