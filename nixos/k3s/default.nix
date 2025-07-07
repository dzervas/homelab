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

  # Required by ceph
  boot.kernelModules = ["rbd"];

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

  # Garage folder
  systemd.services.k3s.serviceConfig.ExecStartPre = ''
    /bin/sh -c "mkdir -p /var/lib/garage/{meta,data}; chown -R 1000:1000 /var/lib/garage/{meta,data}"
  '';
}
