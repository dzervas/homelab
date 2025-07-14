{ home-vpn-iface, node-vpn-iface, ... }: {
  networking.firewall = {
    trustedInterfaces = [ node-vpn-iface ];

    allowedTCPPorts = [ 80 443 ]; # HTTP/S access to the cluster
    interfaces.${home-vpn-iface}.allowedTCPPorts = [ 6443 ]; # Kubernetes API

    filterForward = true;

    # Allow pod & service traffic
    extraInputRules = ''
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
    '';
    # Allow pod & service routing through k3s interface
    extraForwardRules = ''
      # Cluster -> host traffic
      oifname ${node-vpn-iface} ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept

      # Host -> cluster traffic
      iifname ${node-vpn-iface} ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept

      # Host -> host traffic over the VPN
      iifname ${node-vpn-iface} oifname ${node-vpn-iface} accept

      # Allow pod & service traffic between nodes
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept

      # Enable internet
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } oifname { eth0, enp* } accept
    '';
  };

  # Have a 100% concrete and clean DNS config - avoids potential local DHCP/DNS fuckery
  # environment.etc."rancher/rke2/resolv.conf".text = ''
  #   nameserver 1.1.1.1
  #   nameserver 1.0.0.1
  # '';
}
