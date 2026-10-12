local dind = import '../forgejo/dind.libsonnet';
local jobPolicy = import '../forgejo/native-job-policy.libsonnet';
local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local ciliumNetworkPolicy = cilium.cilium.v2.ciliumNetworkPolicy;
local container = k.core.v1.container;
local job = k.batch.v1.job;
local pod = k.core.v1.pod;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

local namespace = 'forgejo-dind-canary';
local configName = 'dind-canary';
local dockerHost = 'unix:///run/dind/docker.sock';
// Newest Docker 29 patch with runc 1.3.5 on both arches; 29.6.0 introduced runc 1.3.6's strict tmpfs mask limits
// Our gVisor 20260406.0 lacks nr_blocks; release-20260714.0 first supports both nr_blocks and nr_inodes
// Fix: https://github.com/google/gvisor/pull/13614 (release tag = 9cb44186726ee4ce882b1246ecaa4c8237406a04)
// That release removes this newer-Docker tmpfs blocker, not a compatibility guarantee for all future versions
// Archived official image, not LTS/maintained: security updates require a deliberate compatibility retest
local dockerVersion = dind.version;
local policy = jobPolicy(namespace, dind=true, name='forgejo-dind-canary-security');
local scripts = {
  'start-dockerd.sh': dind.startupScript,
  'test-dind.sh': importstr './test-dind.sh',
};
local sandbox =
  container.securityContext.withAllowPrivilegeEscalation(false)
  + container.securityContext.capabilities.withDrop(['ALL']);

local template(arch) =
  pod.metadata.withLabels({ app: 'forgejo-dind-canary', arch: arch })
  + pod.metadata.withAnnotations({
    'checksum/config': std.md5(std.manifestJson(scripts)),
  } + dind.annotations)
  + pod.spec.withRuntimeClassName('gvisor-dind')
  + pod.spec.withNodeSelector({ 'kubernetes.io/arch': arch })
  + pod.spec.withRestartPolicy('Never')
  + pod.spec.withAutomountServiceAccountToken(false)
  + pod.spec.withEnableServiceLinks(false)
  + pod.spec.withTerminationGracePeriodSeconds(30)
  + pod.spec.securityContext.seccompProfile.withType('RuntimeDefault')
  + pod.spec.withVolumes([
    volume.fromConfigMap('scripts', configName),
    volume.fromEmptyDir('dind-socket')
    + volume.emptyDir.withMedium('Memory')
    + volume.emptyDir.withSizeLimit('16Mi'),
    volume.fromEmptyDir('docker-data') + volume.emptyDir.withSizeLimit('2Gi'),
    volume.fromEmptyDir('workspace') + volume.emptyDir.withSizeLimit('64Mi'),
  ])
  + pod.spec.withInitContainers([
    container.new('dind', 'docker:' + dockerVersion + '-dind')
    + sandbox
    // SYS_ADMIN requires a daemon-only sandbox exception; the tester stays capability-free
    + container.securityContext.withAllowPrivilegeEscalation(true)
    + container.securityContext.capabilities.withAdd(policy.dindCapabilities)
    + container.withRestartPolicy('Always')
    + container.withCommand(['sh', '/scripts/start-dockerd.sh'])
    + container.withVolumeMounts([
      volumeMount.new('scripts', '/scripts', true),
      volumeMount.new('dind-socket', '/run/dind'),
      volumeMount.new('docker-data', '/var/lib/docker'),
      volumeMount.new('workspace', '/workspace'),
    ])
    + container.startupProbe.exec.withCommand(['docker', 'info'])
    + container.startupProbe.withPeriodSeconds(2)
    + container.startupProbe.withTimeoutSeconds(2)
    + container.startupProbe.withFailureThreshold(60)
    + container.resources.withRequests({ cpu: '100m', memory: '128Mi', 'ephemeral-storage': '256Mi' })
    + container.resources.withLimits({ cpu: '1', memory: '1Gi', 'ephemeral-storage': '3Gi' })
    + container.withEnvMap({
      DOCKER_HOST: dockerHost,
      DOCKER_TLS_CERTDIR: '',
      TZ: timezone,
    }),
  ])
  + pod.spec.withContainers([
    container.new('test', 'docker:' + dockerVersion + '-cli')
    + sandbox
    + container.withCommand(['sh', '/scripts/test-dind.sh'])
    + container.withVolumeMounts([
      volumeMount.new('scripts', '/scripts', true),
      volumeMount.new('dind-socket', '/run/dind'),
      volumeMount.new('workspace', '/workspace'),
    ])
    + container.resources.withRequests({ cpu: '100m', memory: '64Mi', 'ephemeral-storage': '64Mi' })
    + container.resources.withLimits({ cpu: '500m', memory: '256Mi', 'ephemeral-storage': '256Mi' })
    + container.withEnvMap({
      DOCKER_HOST: dockerHost,
      DOCKER_TLS_CERTDIR: '',
      EXPECTED_ARCH: arch,
      TEST_IMAGE: 'alpine:3.23',
      TZ: timezone,
    }),
  ]);

// homelab-42j.3: user-reported live PASS on AMD64/ARM64 (2026-10-12); applying Forgejo never starts this experiment
// Compatibility baseline: Nixpkgs gVisor 20260406.0 + Docker 29.5.3/runc 1.3.5
// Pull/run, shared socket/workspace, bridge service/DNS, HTTPS and BuildKit RUN/export passed
// Docker-managed port publishing is unsupported with iptables disabled; use bridge aliases, not -p
// Rebuild AMD64/ARM64 nodes first, including the shared socket annotation forwarding
// Apply the guard before Jobs: tk apply envs/forgejo-dind-canary -t '.*/.*dind-canary.*' -t '.*/default'
// Image changes require deleting the two existing Jobs first (immutable Pod templates); retain the guard
// Then start tests: tk apply envs/forgejo-dind-canary -t '.*/gvisor-dind-.*'
// Success logs end with GVISOR_DIND_CANARY_PASS <arch>; failed logs remain for 24h
{
  namespace:
    k.core.v1.namespace.new(namespace)
    // PSA baseline rejects sandbox SYS_ADMIN; the namespace-wide CEL guard replaces it
    + k.core.v1.namespace.metadata.withLabels({ 'pod-security.kubernetes.io/enforce': 'privileged' }),

  quota:
    k.core.v1.resourceQuota.new('dind-canary')
    + k.core.v1.resourceQuota.spec.withHard({ pods: '2' }),

  scripts: k.core.v1.configMap.new(configName, scripts),

  jobs: {
    [arch]:
      job.new('gvisor-dind-' + arch)
      + job.spec.withBackoffLimit(0)
      + job.spec.withActiveDeadlineSeconds(900)
      + job.spec.withTtlSecondsAfterFinished(86400)
      + { spec+: { template: template(arch) } }
    for arch in ['amd64', 'arm64']
  },

  networkPolicy:
    ciliumNetworkPolicy.new('dind-canary')
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({})
    + ciliumNetworkPolicy.spec.withEgress([
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'kube-system', 'k8s:k8s-app': 'kube-dns' } }],
        toPorts: [{ ports: [{ port: '53', protocol: 'UDP' }, { port: '53', protocol: 'TCP' }] }],
      },
      { toEntities: ['world'], toPorts: [{ ports: [{ port: '443', protocol: 'TCP' }] }] },
    ]),
} + policy
