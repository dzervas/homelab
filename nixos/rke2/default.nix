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
in {
  imports = [
    ./cron.nix
    ./etcd.nix
    ./firewall.nix
    ./kernel.nix
  ];

  services.rke2 = rec {
    inherit role;

    enable = true;
    tokenFile = "/etc/k3s-token";

    serverAddr = if isMaster then "" else "https://${node-vpn-prefix}.100:9345";

    nodeName = config.networking.hostName;
    nodeIP = "${node-vpn-prefix}.${hostIndex}";
    nodeLabel = [
      "provider=${config.setup.provider}"
      "openebs.io/engine=mayastor"
    ];
    nodeTaint = config.setup.taints;

    # cisHardening = true;
    # selinux = true;

    disable = ["rke2-ingress-nginx"];

    cni = "cilium";
    extraFlags = if role == "server" then [
      "--disable-kube-proxy"
      "--tls-san=${home-vpn-prefix}.${hostIndex},${nodeIP},${config.networking.fqdn}"
      # Don't go checking if the SAN is valid
      # "--tls-san-security=false"
      "--service-node-port-range=25000-32767"
      "--enable-servicelb=false"
      "--advertise-address=${nodeIP}"
    ] else [];
  };
  # systemd.services.rke2-server.enable = false;
}
