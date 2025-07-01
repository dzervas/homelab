{
  config,
  hostIndex,
  home-vpn-prefix,
  home-vpn-iface,
  # node-vpn-prefix,
  # node-vpn-iface,
  pkgs,
  role,
  ...
}: let
  node-vpn-prefix = home-vpn-prefix;
  node-vpn-iface = home-vpn-iface;
  # Denotes the "master" node, where the initial clusterInit happens
  isMaster = hostIndex == "100";
  # Function to convert a set of attributes to k3s flags
  # TODO: Does it handle bools correctly?
  toFlags = attrs: builtins.filter (flag: flag != null)
    (builtins.map
      (name: let
        value = attrs.${name};
      in
        if value == "" || value == null then null
        else if builtins.isBool value && value then "--${name}"
        else "--${name} ${toString value}"
      ) (builtins.attrNames attrs));
in {
  imports = [
    ./etcd.nix
    ./firewall.nix
    ./longhorn.nix
  ];

  services.k3s = {
    inherit role;

    enable = true;
    package = pkgs.k3s_1_31;

    clusterInit = isMaster;
    serverAddr = if isMaster then "" else "https://${node-vpn-prefix}.100:6443";
    tokenFile = "/etc/k3s-token";

    # Gracefully terminate pods when a shutdown is detected
    gracefulNodeShutdown.enable = true;

    extraFlags = toFlags {
      # Common args:
      flannel-iface = node-vpn-iface;
      node-ip = "${node-vpn-prefix}.${hostIndex}";
      node-name = config.networking.fqdn;
      node-label = "provider=${config.setup.provider}";
      resolv-conf = "/etc/rancher/k3s/resolv.conf";

      # TODO: Remove gr1-specific taint from here
      node-taint = builtins.concatStringsSep "," (config.setup.taints ++ (if config.networking.hostName == "gr1" then [ "longhorn=true:NoSchedule" ] else []));
    } ++ (if role != "agent" then toFlags {
      # Server (non-agent) args:
      advertise-address = "${node-vpn-prefix}.${hostIndex}";

      # Allow minecraft as nodeport
      service-node-port-range = "25000-32767";

      disable = builtins.concatStringsSep "," [
        "servicelb"
        "traefik"
        "metrics-server"
        "local-storage"
      ];

      # Hardening stuff
      protect-kernel-defaults = true;
      secrets-encryption = true;
      kube-apiserver-arg = builtins.concatStringsSep "," [
        "enable-admission-plugins=NodeRestriction,EventRateLimit"
        # From https://docs.k3s.io/security/hardening-guide#pod-security
        "admission-control-config-file=/var/lib/rancher/k3s/server/psa.yaml"
        # "audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log"
        # "audit-policy-file=/var/lib/rancher/k3s/server/audit.yaml"
        # "audit-log-maxage=30"
        # "audit-log-maxbackup=10"
        # "audit-log-maxsize=100"
      ];
      kube-controller-manager-arg = builtins.concatStringsSep "," [
        "terminated-pod-gc-threshold=10"
        # "event-qps=1000"
        # "event-burst=1000"
      ];
      kubelet-arg = builtins.concatStringsSep "," [
        "streaming-connection-idle-timeout=5m"
        "tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
      ];
      } else toFlags {});
  };
}
