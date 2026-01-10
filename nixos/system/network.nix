{
  config,
  hostName,
  hostIndex,
  lib,
  home-vpn-prefix,
  home-vpn-iface,
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

      extraForwardRules = ''
        # VPN exit node
        iifname ${node-vpn-iface} oifname eth0 ip saddr ${node-vpn-prefix}.0/24 accept
      '';
    };

    # Tailscale by default uses fwmarks n shit to route traffic, which canal removes
    # Adding the route manually fixes it
    interfaces.${home-vpn-iface}.ipv4.routes = [{ address = "${home-vpn-prefix}.0"; prefixLength = 24; }];

    # Cilium is NOT compatible with nftables!
    nftables.enable = true;

    wg-quick.interfaces.${node-vpn-iface} = {
      address = [ "${node-vpn-prefix}.${hostIndex}/32" ];
      listenPort = wireguard-port;
      # Needs to be generated with:
      # touch /etc/wireguard-privkey && chmod 400 /etc/wireguard-privkey && wg genkey > /etc/wireguard-privkey
      privateKeyFile = "/etc/wireguard-privkey";

      # NOTE: Might need this to avoid fighting bird over the pod cidr
      # allowedIPsAsRoutes = false;

      mtu = 1420;

      # Generate the peers based on the `machines` attribute, defined in the flake
      peers = builtins.filter
        (peer: peer != null)
        (lib.attrsets.mapAttrsToList (name: machine:
          if name != hostName && builtins.hasAttr "publicKey" machine then {
            inherit (machine) publicKey;
            # allowedIPs = ["${node-vpn-prefix}.${machine.hostIndex}/32"];
            allowedIPs = ["${node-vpn-prefix}.${machine.hostIndex}/32" "10.42.${machine.hostIndex}.0/24"];

            # Use it as an endpoint only if it's a k3s server
            endpoint = if builtins.hasAttr "role" machine && machine.role == "server" then "${name}.${config.networking.domain}:${toString wireguard-port}" else null;
            persistentKeepalive = if builtins.hasAttr "role" machine && machine.role == "server" then null else 25;
          } else null)
          machines);
    };
  };

  services = {
    # Needs to be manually initialized with:
    # tailscale up --login-server https://vpn.dzerv.art
    tailscale = {
      enable = true;
      openFirewall = true;

      extraSetFlags = [
        # Disable DNS takeover as it fucks up the cluster DNS too
        "--accept-dns=false"
        "--accept-routes=false"

        "--advertise-exit-node"
      ];

      # Needed to advertise exit nodes
      useRoutingFeatures = "server";
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
        "${home-vpn-prefix}.0/24"
        "${node-vpn-prefix}.0/24"
      ];
    };
  };
}
