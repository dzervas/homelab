# GMKtec EVO-X5 Pro: Ryzen AI Max+ PRO 495 (Zen 5, Radeon 8065S), 192GB LPDDR5X.
# Standalone inference box, not an RKE2 node.
{ config, lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  disko.devices.disk.root.device = "/dev/nvme0n1";

  boot = {
    kernelModules = [ "kvm-amd" ];
    initrd.availableKernelModules = [
      "nvme"
      # "thunderbolt"
      "xhci_pci"
      "uas"
      "sd_mod"
    ];

    # The GPU's memory is system RAM mapped through GTT (BIOS: iGPU UMA_SPECIFIED, smallest frame
    # buffer). Maya sizes its expert pool from MemAvailable on Linux APUs, so a big BIOS carve-out
    # hides the RAM from it (2026-11-05: 160G carve-out, ~32% expert hits, ~2 tok/s). Let the GPU map
    # up to 184 GiB of the 192, leaving 8 GiB for the OS. In 4 KiB pages.
    kernelParams = let
      max_gpu_mem_gb = 184;
      gpu_pages = toString ((max_gpu_mem_gb * 1024 * 1024 * 1024) / 4096); # 4kB per page
    in [
      "ttm.pages_limit=${gpu_pages}"
      "ttm.page_pool_size=${gpu_pages}"
    ];
  };

  # NVMe does its own queueing, so skip the kernel scheduler (`none`). Weights are
  # streamed sequentially (read() or mmap faults), so read ahead 4MB instead of
  # the 128KB default to keep the drive's queue full; RAM is plentiful.
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ENV{DEVTYPE}=="disk", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="4096"
  '';

  system.stateVersion = "26.05";
}
