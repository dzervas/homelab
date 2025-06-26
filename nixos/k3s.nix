{ config, lib, pkgs, ... }: let
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
      "--node-external-ip 10.11.12.${host-index}"
      "--node-name ${config.networking.fqdn}"
      "--node-label provider=home"
      "--resolv-conf /etc/rancher/k3s/resolv.conf"
    ];
  };

  environment.etc."rancher/k3s/resolv.conf".text = "nameserver 1.1.1.1\nnameserver 1.0.0.1";

  networking.firewall = {
    allowedTCPPorts = [ 80 443 ]; # HTTP/S access to the cluster
    filterForward = false;
    # TODO: Avoid this
    trustedInterfaces = [ "zt+" "cni0" "flannel.1" ];

    # Allow pod & service traffic
    extraInputRules = ''
      ip saddr { 10.42.0.0/16, 10.43.0.0/16, 10.11.12.0/24 } accept
      ip daddr { 10.42.0.0/16, 10.43.0.0/16, 10.11.12.0/24 } accept
    '';
    # Allow pod & service routing through k3s interface
    extraForwardRules = ''
      iifname ${vpn-iface} ip saddr { 10.42.0.0/16, 10.43.0.0/16, 10.11.12.0/24 } accept
      oifname ${vpn-iface} ip daddr { 10.42.0.0/16, 10.43.0.0/16, 10.11.12.0/24 } accept
      iifname cni0 accept
      oifname cni0 accept
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
    '';

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

  # Optional dep by longhorn
  boot.kernelModules = lib.mkAfter ["dm_crypt"];
}
