{ node-vpn-iface, ... }:
let
  cni-iface = ''{ "cilium_*", "lxc*" }'';
in
{
  networking.firewall = {
    trustedInterfaces = [ node-vpn-iface ];

    allowedTCPPorts = [
      80
      443
    ]; # HTTP/S access to the cluster

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
