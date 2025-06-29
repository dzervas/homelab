{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "floppy" "sr_mod" "virtio_blk" ];
  nixpkgs.hostPlatform = "x86_64-linux";

  disko.devices.disk.root.device = "/dev/vda";

  setup = {
    provider = "grnet";
    isEFI = false; # No EFI partition required in QEMU
  };
}
