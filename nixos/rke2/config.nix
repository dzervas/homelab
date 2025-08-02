{
  config,
  hostIndex,
  home-vpn-prefix,
  node-vpn-prefix,
  pkgs,
  role,
  ...
}: let
  # Denotes the "master" node, where the initial clusterInit happens
  isMaster = hostIndex == "100";
  nodeIP = "${node-vpn-prefix}.${hostIndex}";
in {
  environment.etc."rancher/rke2/config.yaml".text = builtins.toJSON ({
    node-name = config.networking.hostName;
    node-taint = config.setup.taints;
    node-label = [
      "provider=${config.setup.provider}"
      "openebs.io/engine=mayastor"
    ];

    resolv-conf = "/etc/rancher/rke2/resolv.conf";
  } // (if role == "server" then {
    cni = "canal";
    advertise-address = nodeIP;
    service-node-port-range = "25000-32767";

    etcd-snapshot-compress = true;
    etcd-snapshot-schedule-cron = "0 */12 * * *";
    etcd-snapshot-retention = 20; # 10 days worth of snapshots

    kube-apiserver-arg = [
      # Faster (was 300) dead node pod rescheduling
      "--default-not-ready-toleration-seconds=30"
      "--default-unreachable-toleration-seconds=30"
    ];

    enable-servicelb = false;
    # TODO: Check if rke2-ingress-nginx is better
    disable = [ "rke2-ingress-nginx" ];

    tls-san = [
      "${home-vpn-prefix}.${hostIndex}"
      nodeIP
      config.networking.fqdn
      "kube.${config.networking.domain}"
    ];

    # TODO: Available in next update v1.31.8+rke2r1:
    # secrets-encryption-provider = "aescbc";

    # protect-kernel-defaults = true;
  } else {}));

  systemd.services."rke2-${role}".restartTriggers = [ config.environment.etc."rancher/rke2/config.yaml".source ];

  # Extra manifests to configure rke2 plugins
  systemd.tmpfiles.settings."10-rke2-config" = if isMaster then (let
    rke2-canal-config = pkgs.writeTextFile {
      name = "rke2-canal-config";
      text = builtins.readFile ./rke2-canal-config.yaml;
    };
    rke2-coredns-config = pkgs.writeTextFile {
      name = "rke2-coredns-config";
      text = builtins.readFile ./rke2-coredns-config.yaml;
    };
  in {
    "/var/lib/rancher/rke2/server/manifests/rke2-canal-config.yaml".C.argument = toString rke2-canal-config;
    "/var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml".C.argument = toString rke2-coredns-config;
  }) else {};
}
