{ home-vpn-iface, node-vpn-iface, ... }: {
	networking.nftables.tables.vpn_split = {
	  family = "ip";
	  content = ''
			chain prerouting {
				type nat hook prerouting priority -101; policy accept;

				# VPN-specific ingress
				iifname ${home-vpn-iface} tcp dport 80  counter redirect to :7080
				iifname ${home-vpn-iface} tcp dport 443 counter redirect to :7443
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

    filterForward = true;

    # Allow pod & service traffic
    extraInputRules = ''
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
    '';
    # Allow pod & service routing through k3s interface
    extraForwardRules = ''
      # Cluster -> host traffic
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } oifname ${node-vpn-iface} accept

      # Host -> cluster traffic
      iifname ${node-vpn-iface} ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept

      # Host -> host traffic over the VPN
      iifname ${node-vpn-iface} oifname ${node-vpn-iface} accept

      # Cluster -> home traffic
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } oifname ${home-vpn-iface} accept

      # Allow pod & service traffic between nodes
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept

      # Enable internet
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } oifname { eth0, enp* } accept
    '';
  };

  # Have a 100% concrete and clean DNS config - avoids potential local DHCP/DNS fuckery
  environment.etc."rancher/rke2/resolv.conf".text = ''
    nameserver 8.8.8.8
    nameserver 1.1.1.1
  '';
}
