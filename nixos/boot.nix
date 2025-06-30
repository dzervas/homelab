{ config, ... }: {
  boot.loader = {
    timeout = 0;
    systemd-boot = {
      enable = config.setup.isEFI;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = config.setup.isEFI;
  };
}
