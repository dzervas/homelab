{ hostIndex, node-vpn-iface, node-vpn-prefix, role, ... }: {
  imports = [
    ./config.nix
    ./cron.nix
    ./etcd.nix
    ./firewall.nix
    ./kernel.nix
  ];

  # Add RKE2 utilities to path (kubectl and friends)
  environment.sessionVariables.PATH = "/var/lib/rancher/rke2/bin";

  # TODO: Add graceful shutdown like the k3s module

  services.rke2 = let
    isMaster = hostIndex == "100";
  in {
    inherit role;

    enable = true;

    # Could be in the config but they need to be here
    nodeIP = "${node-vpn-prefix}.${hostIndex}"; # RKE2 bug recreates the cluster
    # NixOS modules bug doesn't like the default configFile
    tokenFile = if isMaster then null else "/etc/k3s-token";
    serverAddr = if isMaster then "" else "https://${node-vpn-prefix}.100:9345";

    # TODO: Requires https://docs.rke2.io/security/hardening_guide/
    # cisHardening = true;
    # selinux = true;
  };

  # OpenEBS RDMA
  networking.rxe = {
    enable = true;
    interfaces = [ node-vpn-iface ];
  };
}
