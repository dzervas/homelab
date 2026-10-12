{
  config,
  pkgs,
  ...
}:
let
  # gVisor with the systrap platform: no /dev/kvm needed, so it works on the
  # arm64 and nested-virt-less VMs too
  runscConfig = pkgs.writeText "runsc.toml" ''
    binary_name = "${pkgs.gvisor}/bin/runsc"
    root = "/run/containerd/runsc"
    [runsc_config]
      platform = "systrap"
  '';

  # Docker 28+ needs packet writes inside the sandbox; keep this off for ordinary gVisor Pods
  # https://gvisor.dev/docs/tutorials/docker-in-gvisor/
  runscDindConfig = pkgs.writeText "runsc-dind.toml" ''
    binary_name = "${pkgs.gvisor}/bin/runsc"
    root = "/run/containerd/runsc"
    [runsc_config]
      platform = "systrap"
      net-raw = "true"
      allow-packet-socket-write = "true"
  '';

  # RKE2 renders its containerd config from this template. Nothing is on PATH,
  # hence the absolute binary paths.
  containerdConfigTemplate = pkgs.writeText "rke2-containerd-config-v3.toml.tmpl" ''
    {{ template "base" . }}

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'sysbox-runc']
      runtime_type = "io.containerd.runc.v2"
    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'sysbox-runc'.options]
      BinaryName = "${pkgs.sysbox-runc}/bin/sysbox-runc"
      SystemdCgroup = true

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'runsc']
      runtime_type = "io.containerd.runsc.v1"
      runtime_path = "${pkgs.gvisor}/bin/containerd-shim-runsc-v1"
    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'runsc'.options]
      TypeUrl = "io.containerd.runsc.v1.options"
      ConfigPath = "${runscConfig}"

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'runsc-dind']
      runtime_type = "io.containerd.runsc.v1"
      runtime_path = "${pkgs.gvisor}/bin/containerd-shim-runsc-v1"
      # Unify only the socket tmpfs across runner/daemon mount namespaces
      pod_annotations = [ "dev.gvisor.spec.mount.dind-socket.*" ]
    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'runsc-dind'.options]
      TypeUrl = "io.containerd.runsc.v1.options"
      ConfigPath = "${runscDindConfig}"
  '';
in
{
  systemd.tmpfiles.settings."10-rke2-containerd" = {
    "/var/lib/rancher/rke2/agent/etc/containerd/config-v3.toml.tmpl"."L+".argument =
      toString containerdConfigTemplate;
  };

  systemd.services."rke2-${config.services.rke2.role}".restartTriggers = [ containerdConfigTemplate ];

  # Advertise the DinD handler only on nodes rebuilt with this configuration
  services.rke2.nodeLabel = [
    "gvisor-runtime=running"
    "gvisor-dind-runtime=running"
  ];
}
