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

    wireguard.interfaces.${node-vpn-iface} = {
      ips = [ "${node-vpn-prefix}.${hostIndex}/32" ];
      listenPort = wireguard-port;
      # Needs to be generated with:
      # touch /etc/wireguard-privkey && chmod 400 /etc/wireguard-privkey && wg genkey > /etc/wireguard-privkey
      privateKeyFile = "/etc/wireguard-privkey";

      # Do not add the allowed ips as routes to avoid fighting calico's BGP
      # table = "off";
      # allowedIPsAsRoutes = false;
      # Add the routes manually
      # postSetup = ''ip route add ${node-vpn-prefix}.0/24 dev ${node-vpn-iface}'';
      # preShutdown = ''ip route del ${node-vpn-prefix}.0/24 dev ${node-vpn-iface}'';

      mtu = 1420;

      # Generate the peers based on the `machines` attribute, defined in the flake
      peers = builtins.filter
        (peer: peer != null)
        (lib.attrsets.mapAttrsToList (name: machine:
          if name != hostName && builtins.hasAttr "publicKey" machine then {
            inherit name;
	          inherit (machine) publicKey;
            # NOTE: For some reason I had to manually add the allowed IPs for SOME nodes
            # wg set wg0 peer 'Owhi+vyqYtFrSs9bOj8qnEsEvOiXD1zME41rLUQ2KV8=' allowed-ips +10.42.101.0/24
            allowedIPs = ["${node-vpn-prefix}.${machine.hostIndex}/32" "10.42.${machine.hostIndex}.0/24"];

            # Use it as an endpoint only if it's a k3s server
            # TODO: Filter based on provider
            # endpoint = if builtins.hasAttr "role" machine && machine.role == "server" then "${name}.${config.networking.domain}:${toString wireguard-port}" else null;
            endpoint = if name != "srv0" then "${name}.${config.networking.domain}:${toString wireguard-port}" else null;
            # persistentKeepalive = if builtins.hasAttr "role" machine && machine.role == "server" then null else 25;
            persistentKeepalive = if name != "srv0" then null else 25;
            dynamicEndpointRefreshSeconds = if name != "srv0" then null else 5;
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
