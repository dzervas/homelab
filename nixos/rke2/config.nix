{
  config,
  hostName,
  hostIndex,
  hostIP,
  home-vpn-prefix,
  node-vpn-prefix,
  pkgs,
  role,
  ...
}:
let
  # Denotes the "master" node, where the initial clusterInit happens
  is-master = hostIndex == "100";
  node-ip = "${node-vpn-prefix}.${hostIndex}";
in
{
  environment.etc."rancher/rke2/config.yaml".text = builtins.toJSON (
    {
      node-name = config.networking.hostName;
      node-taint = config.setup.taints;
      node-label = [ "provider=${config.setup.provider}" ];

      node-external-ip = hostIP;

      resolv-conf = "/etc/rancher/rke2/resolv.conf";
    }
    // (
      if role == "server" then
        {
          cni = "none";
          disable-kube-proxy = true; # Calico handles it in eBPF mode

          advertise-address = node-ip;
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
            node-ip
            config.networking.fqdn
            "kube.vpn.${config.networking.domain}"
            "${hostName}.ts.${config.networking.domain}"
          ];

          # TODO: Available in next update v1.31.8+rke2r1:
          # secrets-encryption-provider = "aescbc";

          # protect-kernel-defaults = true;
        }
      else
        { }
    )
  );

  systemd = {
    services."rke2-${role}".restartTriggers = [
      config.environment.etc."rancher/rke2/config.yaml".source
    ];

    tmpfiles = {
      # Extra manifests to configure rke2 plugins
      settings."10-rke2-config" =
        if is-master then
          (
            let
              rke2-coredns-config = pkgs.writeTextFile {
                name = "rke2-coredns-config";
                text = builtins.readFile ./rke2-coredns-config.yaml;
              };
            in
            {
              "/var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml".C.argument =
                toString rke2-coredns-config;
            }
          )
        else
          { };

      # Graceful shutdown
      settings."10-rke2-kubelet-config" =
        let
          rke2-kubelet-config = pkgs.writeTextFile {
            name = "rke2-kubelet-config";
            text = ''
              apiVersion: kubelet.config.k8s.io/v1beta1
              kind: KubeletConfiguration
              shutdownGracePeriod: 15m
              shutdownGracePeriodCriticalPods: 5m
            '';
          };
        in
        {
          "/var/lib/rancher/rke2/agent/etc/kubelet.conf.d/10-rke2-kubelet-config.yaml".C.argument =
            toString rke2-kubelet-config;
        };
    };
  };

  # Allow enough time for graceful shutdown
  services.logind.settings.Login.InhibitDelayMaxSec = toString (15 * 60);

  # LVM volumes discovery
  services.udev.packages = with pkgs; [ lvm2 ];
  boot.initrd.services.udev.packages = with pkgs; [ lvm2 ];

  # LINSTOR satellite container mounts /etc/lvm but can't follow NixOS symlinks
  # to /nix/store. Without a readable lvm.conf, it disables udev_sync which
  # breaks /dev/<vgname>/<lvname> symlink creation.
  # Creating a real file here allows the satellite to detect LVM is installed.
  environment.etc."lvm/lvm.conf" = {
    mode = "0644";
    text = ''
      # Minimal LVM config for LINSTOR satellite detection
      # The satellite will merge this with its own settings
      config {
        checks = 1
      }
      activation {
        udev_sync = 1
        udev_rules = 1
      }
    '';
  };
}
