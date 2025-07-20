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
  } // (if role == "server" then {
    cni = "canal";
    advertise-address = nodeIP;
    service-node-port-range = "25000-32767";

    enable-servicelb = false;
    # TODO: Check if rke2-ingress-nginx is better
    disable = [ "rke2-ingress-nginx" ];

    tls-san = [
      "${home-vpn-prefix}.${hostIndex}"
      nodeIP
      config.networking.fqdn
      "kube.${config.networking.domain}"
    ];

    oidc = {
      only_start_if_oidc_is_available = false;
    };

    # TODO: Available in next update v1.31.8+rke2r1:
    # secrets-encryption-provider = "aescbc";
  } else {}));

  systemd.services."rke2-${role}".restartTriggers = [ config.environment.etc."rancher/rke2/config.yaml".source ];

  # Extra manifests to configure rke2 plugins
  systemd.tmpfiles.settings."10-rke2-config" = if isMaster then (let
    rke2-canal-config = pkgs.writeTextFile {
      name = "rke2-canal-config";
      text = builtins.readFile ./rke2-canal-config.yaml;
    };
  in {
    "/var/lib/rancher/rke2/server/manifests/rke2-canal-config.yaml".L.argument = toString rke2-canal-config;
  }) else {};
}
