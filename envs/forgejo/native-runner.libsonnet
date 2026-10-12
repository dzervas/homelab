local cache = import './cache-client.libsonnet';
local dind = import './dind.libsonnet';
local jobPolicy = import './native-job-policy.libsonnet';
local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local ciliumNetworkPolicy = cilium.cilium.v2.ciliumNetworkPolicy;
local container = k.core.v1.container;
local envVar = k.core.v1.envVar;
local pod = k.core.v1.pod;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

local jobNamespace = 'forgejo-runners';
// Nested Docker workloads can share/sniff the Pod network; encrypt registration and Runner's token headers
// Public CA TLS via the existing VPN route (Pod CIDR allowed); never disable certificate verification
local forgejoURL = 'https://git.vpn.dzerv.art';
// Manually managed in forgejo-runners: registration-token (global) and admin-read-token (read:admin PAT)
local authSecret = 'forgejo-runner-auth';
local runnerImage = 'data.forgejo.org/forgejo/runner:13.2.0';
// Shared compatibility pin and archived/not-LTS warning live beside dind.version
local dockerVersion = dind.version;
local dockerImage = 'docker:' + dockerVersion + '-dind';
local policy = jobPolicy(jobNamespace, dind=true);
local startupConfig = 'forgejo-dind-startup';
// Verified AMD64/ARM64 Ubuntu 24.04 LTS workflow tools: Node 24/20, Git, tar, Docker CLI and bundled Buildx
// This is the job tool image, not a claim that the separately pinned Docker 29.5.3 daemon is LTS
// Live ARM64 pull failed restoring gst-ptp-helper's security.capability; shared DinD now uses best-effort xattrs
// Keep Actions acceptance blocked until the lossy workaround is proved with the real image on both arches
local jobImage = 'ghcr.io/catthehacker/ubuntu:act-24.04@sha256:62d572b92f9f32d3427b6d220ad1f9dca9c7b6ffad37d295425037dbff78abaf';
// Flip to k8s only after both-architecture Actions/cache/lifecycle acceptance and explicit production cutover
local labelPrefix = 'k8s-canary';
// Compile-time opt-in for cache canaries only; leave disabled until the live cache gate passes
local cacheEnabled = false;
local configName(arch) = 'forgejo-docker-runner-' + arch;
// Generic work belongs only to AMD64 so KEDA pools do not compete for the same queue
local runnerLabels(arch) = (if arch == 'amd64' then [labelPrefix + ':docker://' + jobImage] else []) + [labelPrefix + '-' + arch + ':docker://' + jobImage];
local runnerConfig(arch) = std.manifestYamlDoc({
  runner: {
    file: '/runner-state/.runner',
    labels: runnerLabels(arch),
    capacity: 1,
    insecure: false,
    timeout: '3h',
    shutdown_timeout: '30s',
    env_file: '/dev/null',
    // Stock Runner binds container.docker_host at /var/run/docker.sock inside jobs, not /run/dind
    envs: { DOCKER_HOST: 'unix:///var/run/docker.sock' } + if cacheEnabled then cache.runnerEnvs else {},
  },
  cache: if cacheEnabled then cache.config else { enabled: false },
  container: { docker_host: dind.socket, workdir_parent: '/workspace', privileged: false, valid_volumes: [] },
});
local jobLabels = { app: 'forgejo-keda-runner', 'app.kubernetes.io/managed-by': 'forgejo-keda' };
local jobSelector = jobLabels { 'k8s:io.kubernetes.pod.namespace': jobNamespace };
local sandbox =
  container.securityContext.withAllowPrivilegeEscalation(false)
  + container.securityContext.capabilities.withDrop(['ALL']);

local runnerPod(arch) =
  pod.metadata.withLabels(jobLabels)
  + pod.metadata.withAnnotations(dind.annotations { 'checksum/config': std.md5(runnerConfig(arch) + dind.startupScript) })
  + pod.spec.withRuntimeClassName('gvisor-dind')  // Shared RuntimeClass is owned by envs/network
  + pod.spec.withNodeSelector({ 'kubernetes.io/arch': arch })
  + pod.spec.withRestartPolicy('Never')
  + pod.spec.withAutomountServiceAccountToken(false)
  + pod.spec.withServiceAccountName('default')
  + pod.spec.withEnableServiceLinks(false)
  + pod.spec.withTerminationGracePeriodSeconds(60)
  + pod.spec.securityContext.seccompProfile.withType('RuntimeDefault')
  + pod.spec.securityContext.withFsGroup(1000)
  + pod.spec.withVolumes([
    volume.fromEmptyDir('runner-config') + volume.emptyDir.withSizeLimit('1Mi'),
    // Runner state/credentials are never mounted in DinD or workflow containers
    volume.fromEmptyDir('runner-data') + volume.emptyDir.withSizeLimit('1Gi'),
    volume.fromEmptyDir('dind-socket') + volume.emptyDir.withMedium('Memory') + volume.emptyDir.withSizeLimit('16Mi'),
    // Cold images and named workflow volumes share a deliberate disk budget; vfs duplicates layers
    volume.fromEmptyDir('docker-data') + volume.emptyDir.withSizeLimit('8Gi'),
    volume.fromConfigMap('dind-startup', startupConfig),
    volume.fromConfigMap(configName(arch), configName(arch)),
    // Stock Runner supplies Docker pull auth; imagePullSecrets only apply to kubelet pulls
    volume.fromSecret('registry-auth', 'ghcr-cluster-secret')
    + volume.secret.withItems([{ key: '.dockerconfigjson', path: 'config.json' }])
    + volume.secret.withDefaultMode(288),  // 0440; readable by the stock Runner through fsGroup 1000
  ] + if cacheEnabled then [
    // Only Runner sees the signing key and its generated private config
    volume.fromSecret('cache-signing', cache.secretName)
    + volume.secret.withItems([{ key: cache.secretKey, path: cache.secretKey }])
    + volume.secret.withDefaultMode(288),  // 0440; fsGroup makes it readable by the stock nonroot Runner
    volume.fromEmptyDir('private-config') + volume.emptyDir.withMedium('Memory') + volume.emptyDir.withSizeLimit('1Mi'),
  ] else [])
  + pod.spec.withInitContainers([
    // Native sidecar starts before registration and is terminated automatically after the worker exits
    container.new('dind', dockerImage)
    + sandbox
    + container.securityContext.withAllowPrivilegeEscalation(true)
    + container.securityContext.capabilities.withAdd(policy.dindCapabilities)
    + container.securityContext.withRunAsUser(0)
    + container.securityContext.withRunAsGroup(0)
    + container.withRestartPolicy('Always')
    + container.withCommand(['sh', '/scripts/start-dockerd.sh'])
    + container.withVolumeMounts([
      volumeMount.new('dind-startup', '/scripts', true),
      volumeMount.new('dind-socket', '/run/dind'),
      volumeMount.new('docker-data', '/var/lib/docker'),
    ])
    + container.startupProbe.exec.withCommand(['docker', 'info'])
    + container.startupProbe.withPeriodSeconds(2)
    + container.startupProbe.withTimeoutSeconds(2)
    + container.startupProbe.withFailureThreshold(60)
    + container.resources.withRequests({ cpu: '100m', memory: '128Mi', 'ephemeral-storage': '256Mi' })
    + container.resources.withLimits({ cpu: '2', memory: '2Gi', 'ephemeral-storage': '10Gi' })
    + container.withEnvMap({ DOCKER_HOST: dind.socket, DOCKER_TLS_CERTDIR: '', TZ: timezone }),

    // Same image USER as the worker so its private .runner file remains readable without extra capabilities.
    // Only this init sees the reusable registration token; stock Runner saves fresh ephemeral credentials.
    container.new('register', runnerImage)
    + sandbox
    + container.withCommand(['sh', '-ec', |||
      : "${REGISTRATION_TOKEN:?registration token is missing}"
      umask 077
      exec /bin/forgejo-runner --config /config/config.yaml register \
        --no-interactive --ephemeral --instance "$FORGEJO_URL" \
        --name "$POD_NAME" --labels "$RUNNER_LABELS" --token "$REGISTRATION_TOKEN"
    |||])
    + container.withVolumeMounts([
      volumeMount.new(configName(arch), '/config', true),
      volumeMount.new('runner-config', '/runner-state'),
    ])
    + container.withEnv([
      envVar.fromFieldPath('POD_NAME', 'metadata.name'),
      envVar.withName('REGISTRATION_TOKEN')
      + envVar.valueFrom.secretKeyRef.withName(authSecret)
      + envVar.valueFrom.secretKeyRef.withKey('registration-token'),
    ])
    + container.withEnvMap({
      FORGEJO_URL: forgejoURL,
      RUNNER_LABELS: std.join(',', runnerLabels(arch)),
      TZ: timezone,
    }),
  ])
  + pod.spec.withContainers([
    container.new('runner', runnerImage)
    + sandbox
    + container.withCommand(if cacheEnabled then [
      '/usr/bin/dumb-init',
      '--',
      'sh',
      '-ec',
      cache.prepareConfig + '\nexec /bin/forgejo-runner --config /runner-config/config.yaml one-job',
    ] else [
      '/usr/bin/dumb-init',
      '--',
      '/bin/forgejo-runner',
      '--config',
      '/config/config.yaml',
      // Exit on an empty queue so surplus runners drain and KEDA can reconcile
      'one-job',
    ])
    + container.withWorkingDir('/data')
    + container.withVolumeMounts([
      volumeMount.new('runner-config', '/runner-state', true),
      volumeMount.new(configName(arch), '/config', true),
      volumeMount.new('runner-data', '/data'),
      volumeMount.new('dind-socket', '/run/dind'),
      volumeMount.new('registry-auth', '/run/secrets/registry-auth', true),
    ] + if cacheEnabled then [
      volumeMount.new('cache-signing', cache.secretPath, true),
      volumeMount.new('private-config', '/runner-config'),
    ] else [])
    + container.withEnv(if cacheEnabled then [envVar.fromFieldPath('POD_IP', 'status.podIP')] else [])
    + container.resources.withRequests({ cpu: '100m', memory: '128Mi', 'ephemeral-storage': '256Mi' })
    + container.resources.withLimits({ cpu: '2', memory: '2Gi', 'ephemeral-storage': '4Gi' })
    + container.withEnvMap({
      HOME: '/data',
      // Process environment, not runner.envs: workflows must not receive the registry config
      DOCKER_CONFIG: '/run/secrets/registry-auth',
      DOCKER_HOST: dind.socket,
      TZ: timezone,
    }),
  ]);

{
  nativeJobNamespace:
    k.core.v1.namespace.new(jobNamespace)
    // DinD sandbox capabilities need PSA privileged; namespace-wide dind=true CEL guard forbids host access
    + k.core.v1.namespace.metadata.withLabels({
      'pod-security.kubernetes.io/enforce': 'privileged',
      'pod-security.kubernetes.io/enforce-version': 'latest',
      ghcrCreds: 'enabled',
    }),

  // Retain the quota identity; cap six non-terminal Pods (KEDA counts its minimum separately)
  nativeJobQuota:
    k.core.v1.resourceQuota.new('forgejo-native-canary')
    + k.core.v1.resourceQuota.metadata.withNamespace(jobNamespace)
    + k.core.v1.resourceQuota.spec.withHard({ pods: '6' }),

  dindStartupConfig:
    k.core.v1.configMap.new(startupConfig, { 'start-dockerd.sh': dind.startupScript })
    + k.core.v1.configMap.metadata.withNamespace(jobNamespace),

  runnerConfigs: {
    [arch]:
      k.core.v1.configMap.new(configName(arch), { 'config.yaml': runnerConfig(arch) })
      + k.core.v1.configMap.metadata.withNamespace(jobNamespace)
    for arch in ['amd64', 'arm64']
  },

  // KEDA uses the read-only API token; it is never passed to runner containers
  runnerScalerAuthentication: {
    apiVersion: 'keda.sh/v1alpha1',
    kind: 'TriggerAuthentication',
    metadata: { name: 'forgejo-runners', namespace: jobNamespace },
    spec: { secretTargetRef: [{ parameter: 'token', name: authSecret, key: 'admin-read-token' }] },
  },

  runnerPools: {
    [arch]: {
      apiVersion: 'keda.sh/v1alpha1',
      kind: 'ScaledJob',
      metadata: {
        name: 'keda-k8s-' + arch,
        namespace: jobNamespace,
        // KEDA copies ScaledJob labels to Jobs; do not let tk prune mistake live Jobs for stale manifests
        annotations: { 'scaledjob.keda.sh/job-excluded-labels': 'tanka.dev/environment' },
      },
      spec: {
        pollingInterval: 10,
        minReplicaCount: 0,
        maxReplicaCount: 2,
        successfulJobsHistoryLimit: 1,
        failedJobsHistoryLimit: 1,
        rollout: { strategy: 'gradual' },  // Do not kill running builds on template updates
        // Forgejo's metric includes waiting AND running jobs; use the default strategy
        scalingStrategy: { strategy: 'default' },
        jobTargetRef: {
          parallelism: 1,
          completions: 1,
          backoffLimit: 0,  // Never retry a job with a consumed ephemeral credential
          ttlSecondsAfterFinished: 300,
          // Bound registration/startup and task execution independently of the runner timeout
          activeDeadlineSeconds: 6 * 60 * 60,
          template: runnerPod(arch),
        },
        triggers: [{
          type: 'forgejo-runner',
          metadata: {
            address: forgejoURL,
            global: 'true',
            labels: std.join(',', [std.split(label, ':')[0] for label in runnerLabels(arch)]),
          },
          authenticationRef: { name: 'forgejo-runners' },
        }],
      },
    }
    for arch in ['amd64', 'arm64']
  },

  // Retain the old policy identity so the old proxy egress grant is removed on apply
  nativeJobNetworkPolicy:
    ciliumNetworkPolicy.new('forgejo-native-canary')
    + ciliumNetworkPolicy.metadata.withNamespace(jobNamespace)
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({})
    + ciliumNetworkPolicy.spec.withEgress([
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'kube-system', 'k8s:k8s-app': 'kube-dns' } }],
        toPorts: [{ ports: [{ port: '53', protocol: 'UDP' }, { port: '53', protocol: 'TCP' }] }],
      },
      // Forgejo API and registry use public CA HTTPS; VPN DNS resolves to Traefik, not world
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'traefik', 'app.kubernetes.io/name': 'traefik' } }],
        toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }], serverNames: ['git.vpn.dzerv.art'] + if cacheEnabled then ['forgejo-cache.vpn.dzerv.art'] else [] }],
      },
      { toEntities: ['world'], toPorts: [{ ports: [{ port: '443', protocol: 'TCP' }] }] },
    ]),

  runnerRegistryIngress:
    ciliumNetworkPolicy.new('forgejo-ci-registry')
    + ciliumNetworkPolicy.metadata.withNamespace('traefik')
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({ 'app.kubernetes.io/name': 'traefik' })
    + ciliumNetworkPolicy.spec.withIngress([{
      fromEndpoints: [{ matchLabels: jobSelector }],
      toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }] }],
    }, {
      // HTTPS scaler polling must be allowed at both ends, not just for worker Pods
      fromEndpoints: [{ matchLabels: {
        'k8s:io.kubernetes.pod.namespace': 'keda',
        'app.kubernetes.io/name': 'keda-operator',
      } }],
      toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }] }],
    }]),

  nativeJobForgejoIngress:
    ciliumNetworkPolicy.new('forgejo-runners')
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({ app: 'forgejo' })
    + ciliumNetworkPolicy.spec.withIngress([{
      // Retain the policy identity while removing direct cleartext API access from native jobs/KEDA
      fromEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'traefik', 'app.kubernetes.io/name': 'traefik' } }],
      toPorts: [{ ports: [{ port: '80', protocol: 'TCP' }] }],
    }]),

  // Cache integration is gated separately (homelab-42j.5); retain legacy Sysbox/cache as rollback
  // Production promotion requires real Actions, lifecycle and storage/performance acceptance on both arches
  // Docker-managed published ports are unsupported with iptables=false; services must use bridge aliases
} + policy
