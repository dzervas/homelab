{
  config,
  hostName,
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
      "linstor/enable=true"
    ];

    resolv-conf = "/etc/rancher/rke2/resolv.conf";
  } // (if role == "server" then {
    cni = "calico";
    # disable-kube-proxy = true; # Calico handles it in eBPF mode

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
      "kube.vpn.${config.networking.domain}"
      "${hostName}.ts.${config.networking.domain}"
    ];

    # TODO: Available in next update v1.31.8+rke2r1:
    # secrets-encryption-provider = "aescbc";

    # protect-kernel-defaults = true;
  } else {}));

  systemd.services."rke2-${role}".restartTriggers = [ config.environment.etc."rancher/rke2/config.yaml".source ];

  # Extra manifests to configure rke2 plugins
  systemd.tmpfiles.settings."10-rke2-config" = if isMaster then (let
	  rke2-calico-config = pkgs.writeTextFile {
	    name = "rke2-calico-config";
	    text = builtins.readFile ./rke2-calico-config.yaml;
	  };
    rke2-coredns-config = pkgs.writeTextFile {
      name = "rke2-coredns-config";
      text = builtins.readFile ./rke2-coredns-config.yaml;
    };
  in {
	  "/var/lib/rancher/rke2/server/manifests/rke2-calico-config.yaml".C.argument = toString rke2-calico-config;
    "/var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml".C.argument = toString rke2-coredns-config;
  }) else {};

  # Linstor lvm volumes discovery
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

  # Alternative fix that just runs vgscan --mknodes every time a new device appears
  # Fix for LINSTOR satellite running with udev_sync=0
  # This rule triggers vgscan to create LVM symlinks when DM devices appear
  # services.udev.extraRules = ''
  #   # When a DM device with LVM UUID appears, create the VG symlinks if missing
  #   ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="dm-*", ENV{DM_UUID}=="LVM-*", \
  #     RUN+="${pkgs.lvm2}/bin/vgscan --mknodes"
  # '';
}

# For some reason, the tigera-operator (calico's operator) didn't find an IPPool and I had to create it manually:
# apiVersion: crd.projectcalico.org/v1
# kind: IPPool
# metadata:
#   name: gr0
# spec:
#   cidr: 10.42.0.0/24
#   blockSize: 24
#   ipipMode: Never
#   vxlanMode: Never
#   nodeSelector: "kubernetes.io/hostname == 'gr0'"
