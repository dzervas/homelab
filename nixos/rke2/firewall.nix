{ home-vpn-iface, node-vpn-iface, ... }:
let
  cni-iface = ''{ "cilium_*", "lxc*" }'';
in
{
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

    allowedTCPPorts = [
      80
      443
    ]; # HTTP/S access to the cluster
    interfaces.${home-vpn-iface}.allowedTCPPorts = [
      # Kubernetes API
      6443

      # Home VPN ingress
      7080
      7443
    ];

    # Allow pod & service traffic
    extraInputRules = ''
      iifname ${cni-iface} accept
    '';

    filterForward = true;
    # Allow pod & service routing through k3s interface
    extraForwardRules = ''
      # Always allow established/related early
      ct state { established, related } accept

      # Calico interfaces (veth pairs, etc.)
      iifname ${cni-iface} accept
      oifname ${cni-iface} accept

      # Host -> host traffic over the VPN
      iifname ${node-vpn-iface} oifname ${node-vpn-iface} accept
      iifname ${home-vpn-iface} oifname { eth0, enp* } accept

      # Enable internet (podman and kubernetes)
      iifname podman0 oifname { eth0, enp* } accept
    '';

    extraReversePathFilterRules = ''
      	    iifname ${cni-iface} accept
           meta mark & 0xf00 == 0x200 accept comment "Cilium TPROXY mark - bypass rpfilter"
    '';
  };

  # Have a 100% concrete and clean DNS config - avoids potential local DHCP/DNS fuckery
  environment.etc."rancher/rke2/resolv.conf".text = ''
    nameserver 8.8.8.8
    nameserver 1.1.1.1
  '';
}
