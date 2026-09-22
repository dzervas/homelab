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
}:
let
  wireguard-port = 51820;
in
{
  # Use predictable interface names starting with eth0
  boot.kernelParams = [ "net.ifnames=0" ];

  networking = {
    inherit hostName;
    useDHCP = lib.mkDefault true;
    domain = "dzerv.art";

    dhcpcd.denyInterfaces = [
      "lo"
      node-vpn-iface
      "cali*"
      "podman*"
      "veth*"
    ];

    firewall = {
      enable = true;
      allowedUDPPorts = [ wireguard-port ]; # WireGuard
    };

    # Cilium is NOT compatible with nftables!
    nftables.enable = true;

    wireguard.interfaces.${node-vpn-iface} = {
      ips = [ "${node-vpn-prefix}.${hostIndex}/32" ];
      listenPort = wireguard-port;
      dynamicEndpointRefreshSeconds = 60; # Allows to pick up homelab's dynamic ip change
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
      peers = builtins.filter (peer: peer != null) (
        lib.attrsets.mapAttrsToList (
          name: machine:
          if name != hostName && builtins.hasAttr "publicKey" machine then
            {
              inherit name;
              inherit (machine) publicKey;

              allowedIPs = [ "${node-vpn-prefix}.${machine.hostIndex}/32" ];

              # Use it as an endpoint only if it's a k3s server
              # TODO: Filter based on provider
              # endpoint = if builtins.hasAttr "role" machine && machine.role == "server" then "${name}.${config.networking.domain}:${toString wireguard-port}" else null;
              endpoint =
                if name != "srv0" then "${name}.${config.networking.domain}:${toString wireguard-port}" else null;
              # persistentKeepalive = if builtins.hasAttr "role" machine && machine.role == "server" then null else 25;
              persistentKeepalive = if name != "srv0" && hostName != "srv0" then null else 25;
              dynamicEndpointRefreshSeconds = if name != "srv0" then null else 5;
            }
          else
            null
        ) machines
      );
    };
  };

  services.fail2ban = {
    enable = true;
    ignoreIP = [
      "127.0.0.1/8"
      "${home-vpn-prefix}.0/24"
      "${node-vpn-prefix}.0/24"
    ];
  };

}
