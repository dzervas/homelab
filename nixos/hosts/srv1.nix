{ modulesPath, lib, ... }: {
  # Thanks to https://blog.janissary.xyz/posts/nixos-install-custom-image
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # SD card
  disko.devices.disk.root.device = "/dev/disk/by-label/NIXOS_SD";

  # nixos-generate specifics:
  setup.noBootloader = true;
  fileSystems."/" = {
    device = lib.mkForce "/dev/mainpool/root";
    fsType = lib.mkForce "f2fs";
  };
}

# To build the initial image:
# nixos-generate -f sd-aarch64 --flake ./nixos#srv1 --system aarch64-linux -o ./srv1.sd
# zstdcat -d srv1.sd/sd-image/*.img.zst | sudo dd bs=4M status=progress conv=fsync oflag=direct of=/dev/sdX
