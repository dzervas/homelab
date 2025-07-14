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
}: let
  wireguard-port = 51820;
in {
  # Use predictable interface names starting with eth0
  boot.kernelParams = [ "net.ifnames=0" ];

  networking = {
    inherit hostName;
    useDHCP = lib.mkDefault true;
    domain = "dzerv.art";

    firewall = {
      enable = true;
      allowedUDPPorts = [ wireguard-port ]; # WireGuard
    };

    # NOTE: Cilium is NOT compatible with nftables!
    nftables.enable = true;

    wg-quick.interfaces.${node-vpn-iface} = {
      address = [ "${node-vpn-prefix}.${hostIndex}/32" ];
      listenPort = wireguard-port;
      # Needs to be generated with:
      # touch /etc/wireguard-privkey && chmod 400 /etc/wireguard-privkey && wg genkey > /etc/wireguard-privkey
      privateKeyFile = "/etc/wireguard-privkey";

      # Generate the peers based on the `machines` attribute, defined in the flake
      peers = builtins.filter
        (peer: peer != null)
        (lib.attrsets.mapAttrsToList (name: machine:
          if name != hostName && builtins.hasAttr "publicKey" machine then {
            inherit (machine) publicKey;
            allowedIPs = ["${node-vpn-prefix}.${machine.hostIndex}/32"];

            # Use it as an endpoint only if it's a k3s server
            endpoint = if builtins.hasAttr "role" machine && machine.role == "server" then "${name}.${config.networking.domain}:${toString wireguard-port}" else null;
            persistentKeepalive = if builtins.hasAttr "role" machine && machine.role == "server" then null else 25;
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
      localConf.settings.interfacePrefixBlacklist = [
        # Flannel/Canal
        "flannel"
        "cni"
        "veth"

        # Calico/Canal
        "cali"

        # Cilium
        "cilium_"
        "lxc"

        # WireGuard
        node-vpn-iface
      ];
    };

    wgautomesh = {
      enable = true;
      openFirewall = true;
      gossipSecretFile = "/etc/wgautomesh-secret";

      settings = {
        interface = node-vpn-iface;
        lan_discovery = false;

        # Generate the peers based on the `machines` attribute, defined in the flake
        peers = builtins.filter
          # Filter empty peers
          # Iterate over the machines and create a peer for each one
          (peer: peer != null)
          (lib.attrsets.mapAttrsToList (name: machine:
            if name != hostName && builtins.hasAttr "publicKey" machine then {
              pubkey = machine.publicKey;
              address = "${node-vpn-prefix}.${machine.hostIndex}";

              # Use it as an endpoint only if it's a k3s server
              endpoint = if builtins.hasAttr "role" machine && machine.role == "server" then "${name}.${config.networking.domain}:51820" else null;
            } else null)
            machines);
      };
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
