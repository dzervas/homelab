{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_pci" "virtio_scsi" "usbhid" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];

  networking.useDHCP = true;

  nixpkgs.hostPlatform = "aarch64-linux";

  disko.devices.disk.root.device = "/dev/sda";

  setup.provider = "oracle";
}
