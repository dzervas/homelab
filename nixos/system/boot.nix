{ config, ... }: {
  boot.loader = {
    timeout = 0;

    grub.configurationLimit = 5;

    # EFI
    systemd-boot = {
      enable = config.setup.isEFI;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = config.setup.isEFI;
  };
}
