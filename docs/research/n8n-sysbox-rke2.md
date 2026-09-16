# n8n Sandbox Service with Sysbox on RKE2

Research date: 2026-09-16. Primary sources are linked inline.

## Conclusion

The relevant product is **n8n Sandbox Service**, not n8n's normal Code-node task runner. It has an official, first-party Helm chart in [`n8n-io/n8n-sandbox-service`](https://github.com/n8n-io/n8n-sandbox-service/tree/main/charts/n8n-sandbox-service). Its in-cluster Docker-in-Docker runner defaults to Sysbox. The exact Kubernetes runtime is `sysbox-runc` and its pod must use `hostUsers: false` when RKE2's containerd/Kubernetes combination supports user namespaces.

This repo packages `sysbox-runc`, `sysbox-mgr`, and `sysbox-fs` at v0.7.1 ([`nixos/overlays/_sysbox_versions.nix`](../../nixos/overlays/_sysbox_versions.nix)). The host integration implemented after this research installs the required daemons on `srv1`, registers the RKE2 containerd runtime, and deploys the `RuntimeClass` with the Sandbox Service environment.

More importantly, upstream's supported Kubernetes worker OSes are Ubuntu Noble/Jammy/Focal/Bionic, not NixOS ([requirements](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-k8s.md#kubernetes-worker-node-requirements), [distro matrix](https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md)). The upstream DaemonSet is privileged and mutates `/etc`, `/run`, `/var/lib`, systemd, sysctls and the runtime configuration ([manifest](https://github.com/nestybox/sysbox/blob/master/sysbox-k8s-manifests/sysbox-install.yaml)); it should **not** be applied to these declarative NixOS nodes. A NixOS-native integration is possible only as an untested port: define the daemons, runtime binary path, sysctls, and RKE2 containerd template declaratively, then validate on a dedicated node pool. The supported/low-risk route is a separate Ubuntu RKE2 worker pool for Sysbox.

`arm64` is supported from Sysbox v0.5.0 ([architecture matrix](https://github.com/nestybox/sysbox/blob/master/docs/arch-compat.md)), but that does not make NixOS a supported host OS.

## Required Sysbox/RKE2 registration

Upstream installation labels selected nodes with `sysbox-install=yes`, then installs its `sysbox-deploy-k8s` DaemonSet. The manifest creates:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: sysbox-runc
handler: sysbox-runc
scheduling:
  nodeSelector:
    sysbox-runtime: running
```

Source: [upstream manifest](https://github.com/nestybox/sysbox/blob/master/sysbox-k8s-manifests/sysbox-install.yaml). Thus `runtimeClassName: sysbox-runc` is exact; the handler must be registered under the same name on every eligible node. The installer labels ready nodes `sysbox-runtime=running`, and initially tolerates/uses `sysbox-runtime=not-running:NoSchedule` while it changes the node.

For an RKE2-managed native implementation:

1. Install and run **both** host daemons, `sysbox-mgr` and `sysbox-fs`, alongside the `sysbox-runc` binary. Sysbox's own health checks use `systemctl status sysbox`, `sysbox-mgr`, and `sysbox-fs` ([troubleshooting](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/troubleshoot-k8s.md#sysbox-health-status)). The repo currently provides binaries only.
2. Add containerd handler `sysbox-runc` using `io.containerd.runc.v2` with `BinaryName` pointing at the Nix store path of `sysbox-runc`. This is the shape RKE2 documents for an alternate OCI runtime. RKE2 generates `.../agent/etc/containerd/config.toml`; extend, do not replace, its template: `config-v3.toml.tmpl` for containerd 2.x or `config.toml.tmpl` for 1.7 ([RKE2 advanced configuration](https://docs.rke2.io/advanced#configuring-containerd)).
3. Carry over upstream's host requirements: load `configfs`; install `fuse3`, `rsync`, `iptables`, `newuidmap`/`newgidmap`, and the other runtime helpers; and set Sysbox's sysctls (`kernel.unprivileged_userns_clone`, inotify limits, key limits, `kernel.pid_max`, and `vm.max_map_count`). The authoritative files are [`50-sysbox-mod.conf`](https://github.com/nestybox/sysbox-pkgr/blob/master/k8s/systemd/50-sysbox-mod.conf), [`99-sysbox-sysctl.conf`](https://github.com/nestybox/sysbox-pkgr/blob/master/k8s/systemd/99-sysbox-sysctl.conf), and the upstream systemd units. NixOS also needs explicit handling for upstream hard-coded paths such as `/bin/mount` and `/sbin/iptables*`; merely putting the three packaged binaries in the system closure is insufficient.
4. Restart RKE2/containerd after the template and runtime registration change, then create the `RuntimeClass` above. Verify `kubectl get runtimeclass sysbox-runc`, the runtime configuration on each intended node, and a test pod.
5. Isolate those nodes. Upstream recommends at least 4 CPUs and 4 GiB RAM and documents Kubernetes 1.32--1.35 plus containerd >=2.0.5 for native user namespaces ([Sysbox requirements](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-k8s.md)). The upstream RKE2 instructions likewise say to create the cluster, then follow the Sysbox installation procedure ([RKE2 section](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-k8s-distros.md#rancher-next-gen-kubernetes-engine-rke2)).

Sysbox requires root on the host. Its Kubernetes pods must **not** request `privileged: true`, `hostNetwork`, `hostIPC`, or `hostPID`; those are explicitly unsupported because they defeat the boundary ([limitations](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/limitations.md#kubernetes-restrictions)). Kernel >=5.19 avoids shiftfs; 5.12--5.18 can use ID-mapped mounts but shiftfs is recommended, and <5.12 requires shiftfs ([distro compatibility](https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md#shiftfs-requirement)).

## Exact sandbox chart values and workload

The first-party chart is version 0.7.0 / appVersion 1.3.4 at research time ([Chart.yaml](https://github.com/n8n-io/n8n-sandbox-service/blob/main/charts/n8n-sandbox-service/Chart.yaml)). For an RKE2 containerd node with working Kubernetes user namespaces, its required/default Sysbox selection is:

```yaml
dataPlane:
  mode: in-cluster
runner:
  isolation: sysbox
  sysbox:
    runtime:
      runtimeClassName: sysbox-runc
      hostUsers: false
    scheduling:
      nodeSelector:
        sysbox-install: "yes"
      tolerations:
        - key: sysbox-runtime
          operator: Equal
          value: not-running
          effect: NoSchedule
```

Sources: [chart values](https://github.com/n8n-io/n8n-sandbox-service/blob/main/charts/n8n-sandbox-service/values.yaml), [official Kubernetes quickstart](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/quickstart-k8s.md).

`dataPlane.mode: in-cluster` renders an API `Deployment`, Services/secrets/config, and a Sysbox runner **StatefulSet**. The template writes `runtimeClassName` and `hostUsers` at pod-spec level, uses the Sysbox scheduling sub-block, and does **not** set `privileged: true` for `isolation: sysbox` ([runner StatefulSet](https://github.com/n8n-io/n8n-sandbox-service/blob/main/charts/n8n-sandbox-service/templates/runner-statefulset.yaml)). It runs `n8nio/n8n-sandbox-service-runner-dind`, which needs Docker-in-Docker capability supplied by Sysbox; sandbox containers are then created by that inner Docker daemon. Give each replica its own Docker-data PVC for practical `overlay2` use; the chart renders a per-replica `volumeClaimTemplates` claim when `runner.dockerDataRoot.persistence.enabled: true` ([chart README](https://github.com/n8n-io/n8n-sandbox-service/blob/main/charts/n8n-sandbox-service/README.md#sysbox-scheduling-defaults)).

If the node uses Sysbox's CRI-O fallback instead of suitable containerd, omit `hostUsers` and use:

```yaml
runner:
  sysbox:
    runtime:
      runtimeClassName: sysbox-runc
      hostUsers: null
  podAnnotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
```

That is Sysbox's documented CRI-O user-namespace interface ([Sysbox deployment guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/deploy.md#deploying-pods-with-kubernetes--sysbox)) and is repeated by the first-party chart quickstart. Do not select this fallback casually: upstream says it may install CRI-O and restart kubelet, recreating all pods on that node ([installer behavior](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-k8s.md#containerd-requirement)).

The sandbox API needs its auth Secret and four mTLS certificate secrets (or `tls.mode: certManager`); API-to-runner registration/control is mTLS ([chart README](https://github.com/n8n-io/n8n-sandbox-service/blob/main/charts/n8n-sandbox-service/README.md#tls-secrets)). n8n itself connects by `N8N_SANDBOX_SERVICE_URL` and an API key; the current n8n source constructs the `n8n-sandbox` provider from those settings ([runtime service](https://github.com/n8n-io/n8n/blob/master/packages/cli/src/modules/agents/agent-sandbox-runtime.service.ts)).

## Existing repo workloads and chart provenance

- `envs/n8n/n8n.libsonnet` deploys the n8n **StatefulSet** and already enables the task broker (`N8N_RUNNERS_MODE=external`, broker bind `0.0.0.0`).
- `envs/n8n/runners.libsonnet` deploys a separate ordinary `n8nio/runners:stable` external Code-node task-runner launcher. It has no `runtimeClassName`, no Docker daemon, and is not the Sandbox Service runner. n8n documents that external task runners are normally a separate `n8nio/runners` container; they execute Code-node JS/Python, whereas Sandbox Service supplies on-demand sandbox environments ([task-runner documentation](https://github.com/n8n-io/n8n-docs/blob/main/docs/deploy/host-n8n/configure-n8n/set-up-task-runners.md)). Do not put Sysbox on the existing n8n StatefulSet merely to support the sandbox service.
- The official general n8n chart is [`n8n-io/n8n-hosting/charts/n8n`](https://github.com/n8n-io/n8n-hosting/tree/main/charts/n8n); its Kubernetes README explicitly calls it official and calls raw manifests tutorial/simple setup material ([source](https://github.com/n8n-io/n8n-hosting/blob/main/kubernetes/README.md)). The older `n8n-kubernetes-hosting` repository is archived.
- `8gears/n8n-helm-chart` is a **community** chart, not an n8n-io repository. It should not be used as evidence for first-party sandbox values. The Sandbox Service chart above is the relevant official chart and is separate from the main n8n chart.

## Recommended rollout boundary

Provision a dedicated, supported Ubuntu RKE2 worker pool; label it `sysbox-install=yes`; install/verify Sysbox there; retain the RuntimeClass scheduling selector; then install the Sandbox Service chart with the Sysbox values and a per-runner PVC. Point n8n at the service only after API/mTLS and a sandbox create/exec test succeed. Keep the existing n8n and ordinary Code-node runner workloads on normal nodes. A NixOS-native port should be treated as an explicit engineering task with a disposable node and rollback plan, not as a Helm-values-only change.
