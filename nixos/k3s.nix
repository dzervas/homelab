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
  # Denotes the "master" node, where the initial clusterInit happens
  isMaster = hostIndex == "100";
in {
  services.k3s = {
    inherit role;

    enable = true;
    package = pkgs.k3s_1_31;

    clusterInit = isMaster;
    serverAddr = if isMaster then "" else "https://10.11.12.100:6443";
    tokenFile = "/etc/k3s-token";

    # Gracefully terminate pods when a shutdown is detected
    gracefulNodeShutdown.enable = true;

    extraFlags = [
      # Common args:
      "--flannel-iface ${vpn-iface}"
      "--node-ip 10.11.12.${hostIndex}"
      # "--node-external-ip 10.11.12.${hostIndex}"
      "--node-name ${config.networking.fqdn}"
      "--node-label provider=${provider}"
      "--resolv-conf /etc/rancher/k3s/resolv.conf"
    ] ++ (if role != "agent" then [
      # Server (non-agent) args:
      "--advertise-address 10.11.12.${hostIndex}"
      # Allow minecraft as nodeport
      "--service-node-port-range 25000-32767"
      "--disable ${builtins.concatStringsSep "," [
        "servicelb"
        "traefik"
        "metrics-server"
        "local-storage"
      ]}"

      # Hardening stuff
      "--protect-kernel-defaults"
      "--secrets-encryption"
      "--kube-apiserver-arg ${builtins.concatStringsSep "," [
        "enable-admission-plugins=NodeRestriction,EventRateLimit"
        # From https://docs.k3s.io/security/hardening-guide#pod-security
        "admission-control-config-file=/var/lib/rancher/k3s/server/psa.yaml"
        # "audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log"
        # "audit-policy-file=/var/lib/rancher/k3s/server/audit.yaml"
        # "audit-log-maxage=30"
        # "audit-log-maxbackup=10"
        # "audit-log-maxsize=100"
      ]}"
      "--kube-controller-manager-arg ${builtins.concatStringsSep "," [
        "terminated-pod-gc-threshold=10"
      ]}"
      "--kubelet-arg ${builtins.concatStringsSep "," [
        "streaming-connection-idle-timeout=5m"
        "tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
      ]}"
      # Does it need a custom tls-san too?
    ] else []);
  };

  # Have a 100% concrete and clean DNS config - avoids potential local DHCP/DNS fuckery
  environment.etc."rancher/k3s/resolv.conf".text = ''
    nameserver 1.1.1.1
    nameserver 1.0.0.1
  '';

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
