{ config, hostName, hostIndex, lib, node-vpn-prefix, machines, ... }: {
  networking = {
    inherit hostName;
    domain = "dzerv.art";

    firewall.enable = true;
    nftables.enable = true;

    wg-quick.interfaces.wg0 = {
      address = [ "${node-vpn-prefix}.${hostIndex}/24" ];
      listenPort = 51820;
      # Needs to be generated with:
      # wg genkey > /etc/wireguard-privkey && chmod 400 /etc/wireguard-privkey
      privateKeyFile = "/etc/wireguard-privkey";

      # Generate the peers based on the `machines` attribute, defined in the flake
      peers = builtins.filter
        (peer: peer != null)
        (lib.attrsets.mapAttrsToList (name: machine:
          if name != hostName && builtins.hasAttr "publicKey" machine then {
            inherit (machine) publicKey;
            endpoint = "${name}.${config.networking.domain}:51820";
            allowedIPs = ["${node-vpn-prefix}.${machine.hostIndex}/32"];
          } else null)
          machines);
    };
  };

  services = {
    # Needs to be manually initialized with:
    # zerotier-cli join <network-id>
    zerotierone.enable = true;

    fail2ban = {
      enable = true;
      ignoreIP = [
        "127.0.0.1/8"
        "10.9.8.0/24"
        "10.11.12.0/24"
        "${node-vpn-prefix}.0/24"
      ];
    };
  };
}
