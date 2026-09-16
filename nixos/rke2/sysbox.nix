{
  config,
  lib,
  pkgs,
  ...
}:
let
  containerdConfigTemplate = pkgs.writeText "rke2-sysbox-config-v3.toml.tmpl" ''
    {{ template "base" . }}

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'sysbox-runc']
      runtime_type = "io.containerd.runc.v2"
    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'sysbox-runc'.options]
      BinaryName = "${pkgs.sysbox-runc}/bin/sysbox-runc"
      SystemdCgroup = true
  '';
in
{
  boot = {
    kernelModules = [
      "configfs"
      "fuse"
    ];
    kernel.sysctl = {
      "kernel.unprivileged_userns_clone" = 1;
      "fs.inotify.max_queued_events" = lib.mkForce 1048576;
      "fs.inotify.max_user_watches" = lib.mkForce 1048576;
      "fs.inotify.max_user_instances" = lib.mkForce 1048576;
      "kernel.keys.maxkeys" = 20000;
      "kernel.keys.maxbytes" = 1400000;
      "kernel.pid_max" = 4194304;
      "vm.max_map_count" = 262144;
    };
  };

  environment.systemPackages = with pkgs; [
    sysbox-runc
    sysbox-mgr
    sysbox-fs
    fuse3
    iptables
    kmod
    rsync
    shadow
    procps
    util-linux
  ];

  # Sysbox-runc uses these fixed paths. NixOS packages do not expose the
  # /usr/sbin variants, and /bin is not populated from systemPackages.
  systemd.tmpfiles.rules = [
    "d /sbin 0755 root root - -"
    "d /usr/sbin 0755 root root - -"
    "L+ /bin/mount - - - - ${pkgs.util-linux.bin}/bin/mount"
    "L+ /sbin/iptables - - - - ${pkgs.iptables}/bin/iptables"
    "L+ /sbin/iptables-save - - - - ${pkgs.iptables}/bin/iptables-save"
    "L+ /sbin/iptables-restore - - - - ${pkgs.iptables}/bin/iptables-restore"
    "L+ /usr/sbin/iptables - - - - ${pkgs.iptables}/bin/iptables"
    "L+ /usr/sbin/iptables-save - - - - ${pkgs.iptables}/bin/iptables-save"
    "L+ /usr/sbin/iptables-restore - - - - ${pkgs.iptables}/bin/iptables-restore"
  ];

  systemd.tmpfiles.settings."10-rke2-sysbox" = {
    "/var/lib/rancher/rke2/agent/etc/containerd/config-v3.toml.tmpl"."L+".argument =
      toString containerdConfigTemplate;
  };

  systemd.services = {
    sysbox-mgr = {
      description = "sysbox-mgr (part of the Sysbox container runtime)";
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        iptables
        kmod
        rsync
      ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.sysbox-mgr}/bin/sysbox-mgr --disable-inner-image-preload";
        TimeoutStartSec = "45s";
        TimeoutStopSec = "90s";
        NotifyAccess = "main";
        Restart = "on-failure";
        RestartSec = "10s";
        OOMScoreAdjust = -500;
        LimitNOFILE = "infinity";
        LimitNPROC = "infinity";
      };
    };

    sysbox-fs = {
      description = "sysbox-fs (part of the Sysbox container runtime)";
      after = [ "sysbox-mgr.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.sysbox-fs}/bin/sysbox-fs";
        TimeoutStartSec = "10s";
        TimeoutStopSec = "10s";
        NotifyAccess = "main";
        Restart = "on-failure";
        RestartSec = "10s";
        OOMScoreAdjust = -500;
        LimitNOFILE = "infinity";
        LimitNPROC = "infinity";
      };
    };

    "rke2-${config.services.rke2.role}" = {
      after = [
        "sysbox-mgr.service"
        "sysbox-fs.service"
      ];
      requires = [
        "sysbox-mgr.service"
        "sysbox-fs.service"
      ];
      path = with pkgs; [
        procps
        shadow
        util-linux
      ];
      restartTriggers = [ containerdConfigTemplate ];
    };
  };

  # RKE2 command-line labels take precedence over config.yaml labels, so retain
  # the shared labels while advertising the runtime once both daemons are up.
  services.rke2.nodeLabel = [
    "provider=${config.setup.provider}"
    "topology.kubernetes.io/zone=${config.setup.provider}"
    "sysbox-runtime=running"
  ];
}
