_: {
  boot.loader = {
    timeout = 0;
    systemd-boot = {
      enable = true;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = true;
  };
}
