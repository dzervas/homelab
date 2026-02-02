{
  config,
  hostIndex,
  node-vpn-prefix,
  role,
  ...
}:
{
  imports = [
    ./config.nix
    ./etcd.nix
    ./firewall.nix
    ./kernel.nix
    ./metrics.nix
  ];

  # TODO: Add graceful shutdown like the k3s module
  services.rke2 = let
    is-master = hostIndex == "100";
  in {
    inherit role;

    enable = true;

    # Could be in the config but they need to be here
    nodeIP = "${node-vpn-prefix}.${hostIndex}"; # RKE2 bug recreates the cluster
    # TODO: Define external ip
    # NixOS modules bug doesn't like the default configFile
    tokenFile = if is-master then null else "/etc/k3s-token";
    serverAddr = if is-master then "" else "https://${node-vpn-prefix}.100:9345";

    # TODO: Requires https://docs.rke2.io/security/hardening_guide/
    # cisHardening = true;
    # selinux = true;

    # TODO: Needs https://docs.rke2.io/add-ons/import-images
    # images = [
    #   (pkgs.dockerTools.buildImage {
    #     name = "netshoot";
    #     tag = "latest";
    #     fromImage = pkgs.dockerTools.pullImage {
    #       imageName = "ghcr.io/nicolaka/netshoot";
    #       imageDigest = "sha256:7f08c4aff13ff61a35d30e30c5c1ea8396eac6ab4ce19fd02d5a4b3b5d0d09a2"; # v0.14
    #       sha256 = "sha256-lqZZo6KC8zSeisi++1HFpmUMUQ53345O7swAzeH73XQ=";
    #     };

    #     config = {
    #       User = "65532:65532";
    #       WorkingDir = "/tmp";
    #     };
    #   })
    # ];
  };

  # Add RKE2 utilities to path (kubectl and friends)
  environment.sessionVariables = {
    KUBECONFIG = "/etc/rancher/rke2/rke2.yaml";
    PATH = "/var/lib/rancher/rke2/bin";
    CRI_CONFIG_FILE = "/var/lib/rancher/rke2/agent/etc/crictl.yaml";
  };

  # Remove old k3s container images daily
  services.cron.systemCronJobs = [ "@daily /var/lib/rancher/rke2/bin/crictl rmi --prune --config ${config.environment.sessionVariables.CRI_CONFIG_FILE}" ];
}
