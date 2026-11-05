# GMKtec EVO-X5 Pro: Ryzen AI Max+ PRO 495 (Zen 5, Radeon 8065S), 192GB LPDDR5X.
# Standalone inference box, not an RKE2 node.
{ config, lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "thunderbolt"
    "xhci_pci"
    "uas"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  disko.devices.disk.root.device = "/dev/nvme0n1";

  # NVMe does its own queueing, so skip the kernel scheduler (`none`). Weights are
  # streamed sequentially (read() or mmap faults), so read ahead 4MB instead of
  # the 128KB default to keep the drive's queue full; RAM is plentiful.
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ENV{DEVTYPE}=="disk", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="4096"
  '';

  system.stateVersion = "26.05";
}
