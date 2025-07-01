{ role, home-vpn-iface, node-vpn-iface, ... }: {
  networking.firewall = {
    allowedTCPPorts = [
      80 443 # HTTP/S access to the cluster
      9993 # ZeroTier
    ];
    allowedUDPPorts = [
      9993 # ZeroTier
      51820 # WireGuard
    ];
    filterForward = true;

    # Allow pod & service traffic
    extraInputRules = ''
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
    '';
    # Allow pod & service routing through k3s interface
    extraForwardRules = ''
      iifname ${node-vpn-iface} ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      oifname ${node-vpn-iface} ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
    '';

    # TODO: Remove the home-vpn stuff
    interfaces.${home-vpn-iface} = {
      allowedTCPPorts = [ 10250 ]; # Kubelet metrics
      allowedUDPPorts = [ 8472 ]; # Flannel VXLAN
    };
    interfaces.${node-vpn-iface} = {
      # https://docs.k3s.io/installation/requirements#inbound-rules-for-k3s-nodes
      allowedTCPPorts = [
        10250 # Kubelet metrics
      ] ++ (if role != "agent" then [
        2379 # ETCD Server
        2380 # ETCD Server
        6443 # API Server
        9501 # Longhorn
      ] else []);
      allowedUDPPorts = [
        8472 # Flannel VXLAN
      ];
    };
  };

  # Have a 100% concrete and clean DNS config - avoids potential local DHCP/DNS fuckery
  environment.etc."rancher/k3s/resolv.conf".text = ''
    nameserver 1.1.1.1
    nameserver 1.0.0.1
  '';
}
