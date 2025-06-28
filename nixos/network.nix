{ config, ... }: {
  networking = {
    domain = "dzerv.art";
    firewall.enable = true;
    nftables.enable = true;
  };

  services = {
    zerotierone.enable = true;

    wgautomesh = {
      # TODO: Use wgautomesh + cilium
      enable = false;
      gossipSecretFile = "/etc/wgautomesh-secret";
      settings = {
        peers = [
          "gr0.${config.networking.domain}"
          "gr1.${config.networking.domain}"
          "frankfurt0.${config.networking.domain}"
          "frankfurt1.${config.networking.domain}"
        ];
      };
    };

    fail2ban = {
      enable = true;
      ignoreIP = [
        "127.0.0.1/8"
        "10.9.8.0/24"
        "10.11.12.0/24"
      ];
    };
  };
}
