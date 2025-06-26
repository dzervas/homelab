{ config, pkgs, ... }: let
  vpn-iface = "ztrfyoirbv";
  host-index = "150";
in {
  services.k3s = {
    enable = true;
    package = pkgs.k3s_1_31;

    role = "agent";
    serverAddr = "https://10.11.12.100:6443";
    tokenFile = "/etc/k3s-token";

    # Gracefully terminate pods when a shutdown is detected
    gracefulNodeShutdown.enable = true;

    extraFlags = [
      "--flannel-iface ${vpn-iface}"
      "--node-ip 10.11.12.${host-index}"
      "--node-name ${config.networking.fqdn}"
    ];
  };

  networking.firewall = {
    allowedTCPPorts = [ 80 443 ]; # HTTP/S access to the cluster
    filterForward = true;
    # TODO: Avoid this
    trustedInterfaces = [ "zt+" ];

    # Allow pod & service traffic
    extraInputRules = "ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept";
    # Allow pod & service routing through k3s interface
    extraForwardRules = "iifname ${vpn-iface} ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept";

    interfaces.${vpn-iface} = {
      # https://docs.k3s.io/installation/requirements#inbound-rules-for-k3s-nodes
      allowedTCPPorts = [
        # 2379 # ETCD Server - servers only
        # 2380 # ETCD Server - servers only
        # 6443 # API Server - servers only

        # 9501 # Longhorn
        10250 # Kubelet metrics
      ];
      allowedUDPPorts = [
        8472 # Flannel VXLAN
        # 51820 # Flannel wireguard ipv4
        # 51821 # Flannel wireguard ipv6
      ];
    };
  };

  # Required by longhorn
  # https://github.com/longhorn/longhorn/issues/2166#issuecomment-2994323945
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };
  systemd.services.iscsid.serviceConfig = {
    PrivateMounts = "yes";
    BindPaths = "/run/current-system/sw/bin:/bin";
  };
}
