{ home-vpn-iface, node-vpn-iface, ... }: {
  networking.nftables.tables.vpn_split = {
    family = "ip";
    content = ''
      chain prerouting {
        type nat hook prerouting priority mangle - 1; policy accept;

        # VPN-specific ingress
        iifname ${home-vpn-iface} tcp dport 80  counter tcp dport set 7080
        iifname ${home-vpn-iface} tcp dport 443 counter tcp dport set 7443
      }
    '';
  };

  networking.firewall = {
    trustedInterfaces = [ node-vpn-iface ];

    allowedTCPPorts = [ 80 443 ]; # HTTP/S access to the cluster
    interfaces.${home-vpn-iface}.allowedTCPPorts = [
      # Kubernetes API
      6443

      # Home VPN ingress
      7080 7443
    ];

    # Allow pod & service traffic
    extraInputRules = ''
      # Allow Calico IPIP encapsulation over WireGuard
      # ip protocol 4 iifname ${node-vpn-iface} accept

      iifname "cali*" accept
    '';

    filterForward = true;
    # Allow pod & service routing through k3s interface
    extraForwardRules = ''
      # Calico stuff
      # Always allow established/related early
      ct state { established, related } accept

      # Allow Calico IPIP encapsulated traffic
      # ip protocol 4 iifname ${node-vpn-iface} accept
      # ip protocol 4 oifname ${node-vpn-iface} accept

      # Allow pod <-> pod and pod <-> service everywhere
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept

      # BGP migration
      iifname ${node-vpn-iface} oifname ${node-vpn-iface} ip saddr {10.42.0.0/16, 10.43.0.0/16} ip daddr {10.42.0.0/16, 10.43.0.0/16} accept

      # Calico interfaces (veth pairs, etc.)
      iifname "cali*" accept
      oifname "cali*" accept

      # Allow routing between calico and wireguard
      iifname "cali*" oifname ${node-vpn-iface} accept
      iifname ${node-vpn-iface} oifname "cali*" accept
      iifname "cali*" oifname { eth0, enp* } accept
      iifname { eth0, enp* } oifname "cali*" accept

      # Host -> host traffic over the VPN
      iifname ${node-vpn-iface} oifname ${node-vpn-iface} accept

      # Enable internet (podman and kubernetes)
      iifname podman0 oifname { eth0, enp* } accept
    '';
  };

  # Have a 100% concrete and clean DNS config - avoids potential local DHCP/DNS fuckery
  environment.etc."rancher/rke2/resolv.conf".text = ''
    nameserver 8.8.8.8
    nameserver 1.1.1.1
  '';
}
