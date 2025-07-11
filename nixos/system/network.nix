{
  config,
  hostName,
  hostIndex,
  lib,
  home-vpn-prefix,
  node-vpn-prefix,
  node-vpn-iface,
  machines,
  ...
}: {
  # Use predictable interface names starting with eth0
  boot.kernelParams = [ "net.ifnames=0" ];

  networking = {
    inherit hostName;
    useDHCP = lib.mkDefault true;
    domain = "dzerv.art";

    firewall.enable = true;
    nftables.enable = true;

    wg-quick.interfaces.wg0 = {
      address = [ "${node-vpn-prefix}.${hostIndex}/24" ];
      listenPort = 51820;
      # Needs to be generated with:
      # touch /etc/wireguard-privkey && chmod 400 /etc/wireguard-privkey && wg genkey > /etc/wireguard-privkey
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
    zerotierone = {
      enable = true;
      # Don't peek at the k8s interfaces
      localConf.settings.interfacePrefixBlacklist = [ "flannel" "cni" "veth" node-vpn-iface ];
    };

    fail2ban = {
      enable = true;
      ignoreIP = [
        "127.0.0.1/8"
        "10.9.8.0/24"
        "${home-vpn-prefix}.0/24"
        "${node-vpn-prefix}.0/24"
      ];
    };
  };
}
