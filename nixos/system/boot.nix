{ config, ... }: {
  boot.loader = {
    timeout = 0;
    grub.enable = !config.setup.isEFI;
    systemd-boot = {
      enable = config.setup.isEFI;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = config.setup.isEFI;
  };
}
