{
  config,
  hostIndex,
  # node-vpn-prefix,
  # node-vpn-iface,
  home-vpn-prefix,
  home-vpn-iface,
  role,
  ...
}: let
  node-vpn-prefix = home-vpn-prefix;
  node-vpn-iface = home-vpn-iface;
in {
  environment.etc."rancher/k3s/config.yaml".text = builtins.toJSON ({
    # Common args:
    flannel-iface = node-vpn-iface;
    # flannel-backend = "host-gw"; # TODO: Enable this once we have a working host-gw setup

    node-ip = "${node-vpn-prefix}.${hostIndex}";
    node-name = config.networking.fqdn;
    node-label = [
      "provider=${config.setup.provider}"
      "openebs.io/engine=mayastor"
      "openebs.io/csi-node=mayastor"
    ];
    resolv-conf = "/etc/rancher/k3s/resolv.conf";

    node-taint = config.setup.taints;
  } // (if (role != "agent") then {
    # Server (non-agent) args:
    advertise-address = "${node-vpn-prefix}.${hostIndex}";

    # Allow minecraft as nodeport
    service-node-port-range = "25000-32767";

    disable = [
      "servicelb"
      "traefik"
      "metrics-server"
      "local-storage"
    ];

    # Hardening stuff
    protect-kernel-defaults = true;
    secrets-encryption = true;
    # TODO: Enable the admission-control-config-file
    kube-apiserver-arg = [
      "enable-admission-plugins=NodeRestriction,EventRateLimit"
      # From https://docs.k3s.io/security/hardening-guide#pod-security
      "admission-control-config-file=/var/lib/rancher/k3s/server/psa.yaml"
      # "audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log"
      # "audit-policy-file=/var/lib/rancher/k3s/server/audit.yaml"
      # "audit-log-maxage=30"
      # "audit-log-maxbackup=10"
      # "audit-log-maxsize=100"
    ];
    kube-controller-manager-arg = [
      "terminated-pod-gc-threshold=10"
      # "event-qps=1000"
      # "event-burst=1000"
    ];
    kubelet-arg = [
      "streaming-connection-idle-timeout=5m"
      "tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
    ];

    # Server certificate SAN
    tls-san = [
      "127.0.0.1"
      config.networking.fqdn
      "${node-vpn-prefix}.${hostIndex}"
      "10.20.30.${hostIndex}"
    ];
  } else {}));
}
