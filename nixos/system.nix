{ lib, pkgs, ... }: {
  environment.systemPackages = map lib.lowPrio (with pkgs; [
    curl
    git
  ]);

  programs.nix-ld.enable = true;

  services = {
    fwupd.enable = true;
    openssh.enable = true;
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIB9rcx6pJF2ZEJsB5oFWF0E7LKOL5HQlA2uPdvDdafq"
  ];

  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "25.05";
}
