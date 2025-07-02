{ config, ... }: {
  boot.loader = {
    timeout = 0;

    grub = {
      enable = !config.setup.isEFI;
      # device = config.disko.devices.disk.root.device;
      configurationLimit = 5;
    };

    # EFI
    systemd-boot = {
      enable = config.setup.isEFI;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = config.setup.isEFI;
  };
}
