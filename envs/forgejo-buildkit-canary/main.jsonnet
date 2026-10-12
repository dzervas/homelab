local jobPolicy = import '../forgejo/native-job-policy.libsonnet';
local cm = import 'cert-manager-libsonnet/1.19/main.libsonnet';
local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local certificate = cm.nogroup.v1.certificate;
local issuer = cm.nogroup.v1.issuer;
local ciliumNetworkPolicy = cilium.cilium.v2.ciliumNetworkPolicy;
local container = k.core.v1.container;
local pod = k.core.v1.pod;
local service = k.core.v1.service;
local statefulSet = k.apps.v1.statefulSet;
local job = k.batch.v1.job;
local pvc = k.core.v1.persistentVolumeClaim;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

local namespace = 'forgejo-buildkit-canary';
local configName = 'buildkit-canary';
local arches = ['amd64', 'arm64'];
// Stock upstream Dockerfile v0.30.0 pins RUNC_VERSION=v1.3.5; Hub has native AMD64/ARM64
// https://github.com/moby/buildkit/blob/v0.30.0/Dockerfile (client logs verify actual buildkit-runc)
// Fixed compatibility candidate, not LTS or a standalone-runtime PASS; a version archive is no security-update promise
// gVisor baseline 20260406.0 lacks nr_blocks/nr_inodes; release-20260714.0 removes THIS newer-runc blocker only
// https://github.com/google/gvisor/pull/13614; do not substitute moving tags, host runc, privileged or noProcessSandbox
// Docker 29.5.3 embeds this BuildKit version, but its Docker worker PASS does not prove standalone OCI
local image = 'moby/buildkit:v0.30.0';
local policy = jobPolicy(namespace, name='forgejo-buildkit-canary-security', builder=true);
local config = {
  'buildkitd.toml': importstr './buildkitd.toml',
  'test-buildkit.sh': importstr './test-buildkit.sh',
};
local sandbox =
  container.securityContext.withAllowPrivilegeEscalation(false)
  + container.securityContext.capabilities.withDrop(['ALL']);
local labels(arch, role) = { app: configName, arch: arch, role: role };
local serverName(arch) = 'buildkit-' + arch;
local serverDns(arch) = serverName(arch) + '.' + namespace + '.svc';
local commonPod(arch, role) =
  pod.metadata.withLabels(labels(arch, role))
  + pod.metadata.withAnnotations({ 'checksum/config': std.md5(std.manifestJson(config)) })
  + pod.spec.withRuntimeClassName('gvisor-dind')
  + pod.spec.withNodeSelector({ 'kubernetes.io/arch': arch })
  + pod.spec.withAutomountServiceAccountToken(false)
  + pod.spec.withEnableServiceLinks(false)
  + pod.spec.securityContext.seccompProfile.withType('RuntimeDefault');
local leaf(name, usages) =
  certificate.new(name)
  + certificate.spec.withSecretName(name)
  + certificate.spec.withDuration('168h')
  + certificate.spec.withRenewBefore('24h')
  + certificate.spec.privateKey.withAlgorithm('ECDSA')
  + certificate.spec.privateKey.withSize(256)
  + certificate.spec.privateKey.withRotationPolicy('Always')
  + certificate.spec.withUsages(usages)
  + certificate.spec.issuerRef.withName('buildkit-ca')
  + certificate.spec.issuerRef.withKind('Issuer');

// Isolated acceptance only; no Forgejo callers, runner credentials or global device CA
// Apply namespace and guard FIRST (PSA privileged allows virtual SYS_ADMIN; CEL forbids true privileged/host access):
// tk apply envs/forgejo-buildkit-canary -t '.*/forgejo-buildkit-canary' -t '.*/forgejo-buildkit-canary-security' -t '.*/default'
// Inspect guard typeChecking warnings before workloads: kubectl get validatingadmissionpolicy forgejo-buildkit-canary-security -o jsonpath='{.status.typeChecking}'
// Then tk apply envs/forgejo-buildkit-canary (warm Jobs are suspended); no node rebuild/apply is authorized here
// Both cold Jobs must PASS; keep logs (including CACHE_TOKEN) and PVC usage before restarting
// Measure headroom: kubectl -n forgejo-buildkit-canary exec buildkit-amd64-0 -- df -h /var/lib/buildkit; repeat arm64
// kubectl -n forgejo-buildkit-canary logs job/buildkit-cold-amd64; repeat arm64
// Restart without deleting state: kubectl -n forgejo-buildkit-canary delete pod buildkit-amd64-0 buildkit-arm64-0
// kubectl -n forgejo-buildkit-canary rollout status statefulset/buildkit-amd64; repeat arm64
// kubectl -n forgejo-buildkit-canary patch job buildkit-warm-amd64 --type=merge -p '{"spec":{"suspend":false}}'; repeat arm64
// Warm Jobs must PASS, report CACHED RUN and IDENTICAL CACHE_TOKEN to cold logs, with measured state free-space headroom
// Repeat cycle: delete all four Jobs, reapply (warm suspended again), then restart/resume as above
// Servers remain for inspection; cleanup is manual: kubectl delete namespace forgejo-buildkit-canary
// Then kubectl delete validatingadmissionpolicy,validatingadmissionpolicybinding forgejo-buildkit-canary-security
// Namespace cleanup deletes probe PVCs/CA; this 2Gi probe is not a production capacity decision
{
  namespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({ 'pod-security.kubernetes.io/enforce': 'privileged' }),

  quota:
    k.core.v1.resourceQuota.new(configName)
    + k.core.v1.resourceQuota.spec.withHard({
      pods: '6',
      'requests.cpu': '2',
      'limits.cpu': '6',
      'requests.memory': '2Gi',
      'limits.memory': '6Gi',
      'requests.ephemeral-storage': '1Gi',
      'limits.ephemeral-storage': '4Gi',
      persistentvolumeclaims: '2',
      'requests.storage': '4Gi',
    }),

  config: k.core.v1.configMap.new(configName, config),

  selfsigned: issuer.new('buildkit-selfsigned') + { spec+: { selfSigned: {} } },
  ca:
    certificate.new('buildkit-ca')
    + certificate.spec.withSecretName('buildkit-ca')
    + certificate.spec.withCommonName('forgejo-buildkit-canary CA')
    + certificate.spec.withIsCA(true)
    + certificate.spec.withDuration('720h')
    + certificate.spec.privateKey.withAlgorithm('ECDSA')
    + certificate.spec.privateKey.withSize(256)
    + certificate.spec.withUsages(['cert sign', 'crl sign'])
    + certificate.spec.issuerRef.withName('buildkit-selfsigned')
    + certificate.spec.issuerRef.withKind('Issuer'),
  caIssuer: issuer.new('buildkit-ca') + issuer.spec.ca.withSecretName('buildkit-ca'),
  clientCertificate: leaf('buildkit-probe-client', ['client auth']) + certificate.spec.withCommonName('trusted-buildkit-probe'),
  serverCertificates: {
    [arch]:
      leaf(serverName(arch) + '-tls', ['server auth'])
      + certificate.spec.withDnsNames([serverDns(arch), serverDns(arch) + '.cluster.local'])
    for arch in arches
  },

  services: {
    [arch]:
      service.new(serverName(arch), labels(arch, 'server'), [{ name: 'buildkit', port: 1234, targetPort: 1234 }])
    for arch in arches
  },
  builders: {
    [arch]:
      statefulSet.new(serverName(arch))
      + statefulSet.spec.withReplicas(1)
      + statefulSet.spec.withServiceName(serverName(arch))
      + statefulSet.spec.selector.withMatchLabels(labels(arch, 'server'))
      + statefulSet.spec.withVolumeClaimTemplates([
        pvc.new('state')
        + pvc.spec.withAccessModes(['ReadWriteOnce'])
        + pvc.spec.withStorageClassName('longhorn')
        + pvc.spec.resources.withRequests({ storage: '2Gi' }),
      ])
      + { spec+: {
        template:
          commonPod(arch, 'server')
          + pod.spec.withTerminationGracePeriodSeconds(30)
          + pod.spec.withVolumes([
            volume.fromConfigMap('config', configName),
            volume.fromSecret('server-tls', serverName(arch) + '-tls'),
          ])
          + pod.spec.withContainers([
            container.new('buildkit', image)
            + sandbox
            // Root and these caps are virtual to gVisor; no host devices/paths or true privileged
            + container.securityContext.withRunAsUser(0)
            + container.securityContext.withAllowPrivilegeEscalation(true)
            + container.securityContext.capabilities.withAdd(policy.dindCapabilities)
            + container.withCommand(['buildkitd', '--config', '/config/buildkitd.toml', '--oci-worker-platform', 'linux/' + arch])
            + container.withPorts([{ name: 'buildkit', containerPort: 1234 }])
            + container.withVolumeMounts([
              volumeMount.new('state', '/var/lib/buildkit'),
              volumeMount.new('config', '/config', true),
              volumeMount.new('server-tls', '/tls', true),
            ])
            // TCP readiness avoids mounting a trusted client key in the server
            + container.readinessProbe.tcpSocket.withPort(1234)
            + container.readinessProbe.withPeriodSeconds(5)
            + container.resources.withRequests({ cpu: '250m', memory: '256Mi', 'ephemeral-storage': '64Mi' })
            + container.resources.withLimits({ cpu: '2', memory: '2Gi', 'ephemeral-storage': '256Mi' })
            + container.withEnvMap({ TZ: timezone }),
          ]),
      } }
    for arch in arches
  },

  tests: {
    [phase + '-' + arch]:
      job.new('buildkit-' + phase + '-' + arch)
      + job.spec.withSuspend(phase == 'warm')
      + job.spec.withBackoffLimit(0)
      + job.spec.withActiveDeadlineSeconds(900)
      + job.spec.withTtlSecondsAfterFinished(86400)
      + { spec+: {
        template:
          commonPod(arch, 'probe')
          + pod.spec.withRestartPolicy('Never')
          + pod.spec.withVolumes([
            volume.fromConfigMap('config', configName),
            volume.fromSecret('client-tls', 'buildkit-probe-client'),
            volume.fromEmptyDir('workspace') + volume.emptyDir.withSizeLimit('256Mi'),
          ])
          + pod.spec.withContainers([
            container.new('probe', image)
            + sandbox
            + container.withCommand(['sh', '/config/test-buildkit.sh'])
            + container.withVolumeMounts([
              volumeMount.new('config', '/config', true),
              volumeMount.new('client-tls', '/tls', true),
              volumeMount.new('workspace', '/workspace'),
            ])
            + container.resources.withRequests({ cpu: '100m', memory: '128Mi', 'ephemeral-storage': '64Mi' })
            + container.resources.withLimits({ cpu: '500m', memory: '256Mi', 'ephemeral-storage': '512Mi' })
            + container.withEnvMap({
              BUILDKIT_HOST: 'tcp://' + serverDns(arch) + ':1234',
              EXPECTED_ARCH: arch,
              PHASE: phase,
              TZ: timezone,
            }),
          ]),
      } }
    for phase in ['cold', 'warm']
    for arch in arches
  },

  serverNetwork:
    ciliumNetworkPolicy.new('buildkit-server')
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({ app: configName, role: 'server' })
    + ciliumNetworkPolicy.spec.withIngress([{
      fromEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': namespace, 'k8s:app': configName, 'k8s:role': 'probe' } }],
      toPorts: [{ ports: [{ port: '1234', protocol: 'TCP' }] }],
    }])
    + ciliumNetworkPolicy.spec.withEgress([
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'kube-system', 'k8s:k8s-app': 'kube-dns' } }],
        toPorts: [{ ports: [{ port: '53', protocol: 'UDP' }, { port: '53', protocol: 'TCP' }] }],
      },
      { toEntities: ['world'], toPorts: [{ ports: [{ port: '443', protocol: 'TCP' }] }] },
    ]),
  clientNetwork:
    ciliumNetworkPolicy.new('buildkit-probe')
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({ app: configName, role: 'probe' })
    + ciliumNetworkPolicy.spec.withIngress([])
    + ciliumNetworkPolicy.spec.withEgress([
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'kube-system', 'k8s:k8s-app': 'kube-dns' } }],
        toPorts: [{ ports: [{ port: '53', protocol: 'UDP' }, { port: '53', protocol: 'TCP' }] }],
      },
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': namespace, 'k8s:app': configName, 'k8s:role': 'server' } }],
        toPorts: [{ ports: [{ port: '1234', protocol: 'TCP' }] }],
      },
    ]),
} + policy
