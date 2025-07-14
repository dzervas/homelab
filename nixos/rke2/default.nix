{
  config,
  hostIndex,
  home-vpn-prefix,
  node-vpn-prefix,
  role,
  ...
}: let
  # Denotes the "master" node, where the initial clusterInit happens
  isMaster = hostIndex == "100";
  nodeIP = "${node-vpn-prefix}.${hostIndex}";
in {
  imports = [
    ./cron.nix
    ./etcd.nix
    ./firewall.nix
    ./kernel.nix
  ];

  services.rke2 = {
    inherit role nodeIP;

    enable = true;
    tokenFile = "/etc/k3s-token";

    serverAddr = if isMaster then "" else "https://${node-vpn-prefix}.100:9345";

    nodeName = config.networking.hostName;
    nodeLabel = [
      "provider=${config.setup.provider}"
      "openebs.io/engine=mayastor"
    ];
    nodeTaint = config.setup.taints;

    # cisHardening = true;
    # selinux = true;
  } // (if role == "server" then {
    # TODO: Check if rke2-ingress-nginx is better
    disable = ["rke2-ingress-nginx" "rke2-canal"];

    cni = "cilium";
    extraFlags = [
      "--disable-kube-proxy"
      "--tls-san=${home-vpn-prefix}.${hostIndex},${nodeIP},${config.networking.fqdn}"
      "--service-node-port-range=25000-32767"
      "--enable-servicelb=false"
      "--advertise-address=${nodeIP}"
    ];
  } else {});
}
