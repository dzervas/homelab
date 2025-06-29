{
  config,
  hostIndex,
  lib,
  provider,
  pkgs,
  role,
  ...
}: let
  vpn-iface = "ztrfyoirbv";
in {
  services.k3s = {
    inherit role;
    enable = true;
    package = pkgs.k3s_1_31;

    serverAddr = "https://10.11.12.100:6443";
    tokenFile = "/etc/k3s-token";

    # Gracefully terminate pods when a shutdown is detected
    gracefulNodeShutdown.enable = true;

    extraFlags = [
      "--flannel-iface ${vpn-iface}"
      "--node-ip 10.11.12.${hostIndex}"
      "--node-external-ip 10.11.12.${hostIndex}"
      "--node-name ${config.networking.fqdn}"
      "--node-label provider=${provider}"
      "--resolv-conf /etc/rancher/k3s/resolv.conf"
    ];
  };

  # Have a 100% concrete and clean DNS config - avoids potential local DHCP/DNS fuckery
  environment.etc."rancher/k3s/resolv.conf".text = "nameserver 1.1.1.1\nnameserver 1.0.0.1";

  networking.firewall = {
    allowedTCPPorts = [ 80 443 ]; # HTTP/S access to the cluster
    filterForward = true;

    # Allow pod & service traffic
    extraInputRules = ''
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
    '';
    # Allow pod & service routing through k3s interface
    extraForwardRules = ''
      iifname ${vpn-iface} ip saddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      oifname ${vpn-iface} ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
      ip saddr { 10.42.0.0/16, 10.43.0.0/16 } ip daddr { 10.42.0.0/16, 10.43.0.0/16 } accept
    '';

    interfaces.${vpn-iface} = {
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
