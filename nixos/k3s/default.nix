{
  hostIndex,
  home-vpn-prefix,
  # node-vpn-prefix,
  pkgs,
  role,
  ...
}: let
  node-vpn-prefix = home-vpn-prefix;
  # Denotes the "master" node, where the initial clusterInit happens
  isMaster = hostIndex == "100";
in {
  imports = [
    ./config.nix
    ./cron.nix
    ./etcd.nix
    ./firewall.nix
    ./longhorn.nix
  ];

  # Required by openebs
  boot.kernelModules = ["nvme_tcp"];

  services.k3s = {
    inherit role;

    enable = true;
    package = pkgs.k3s_1_31;
    tokenFile = "/etc/k3s-token";

    clusterInit = isMaster;
    serverAddr = if isMaster then "" else "https://${node-vpn-prefix}.100:6443";

    # Gracefully terminate pods when a shutdown is detected
    gracefulNodeShutdown.enable = true;
  };

  # Had to add the following above the `errors` line to the kube-system/coredns configmap to have proper DNS:
  # header {
  # response set ra
  # }
  # according to https://jbn1233.medium.com/kubernetes-kube-dns-fix-nslookup-error-got-recursion-not-available-from-ff9ee86d1823
  # In file /var/lib/rancher/k3s/server/manifests/coredns.yaml
}
