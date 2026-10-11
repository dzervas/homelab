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

local namespace = 'forgejo';
local jobNamespace = 'forgejo-runners';
local forgejoURL = 'http://forgejo.forgejo.svc';
// Manually managed in forgejo-runners: registration-token (global) and admin-read-token (read:admin PAT)
local authSecret = 'forgejo-runner-auth';
local runnerImage = 'data.forgejo.org/forgejo/runner:13';
local jobImage = 'data.forgejo.org/oci/node:lts-trixie';
local configName(arch) = 'forgejo-host-runner-' + arch;
local runnerLabels(arch) = ['k8s:host', 'k8s-' + arch + ':host'];
local runnerConfig(arch) = std.manifestYamlDoc({
  runner: {
    file: '/runner-config/.runner',
    labels: runnerLabels(arch),
    capacity: 1,
    timeout: '3h',
    shutdown_timeout: '30s',
    env_file: '/dev/null',
  },
  cache: { enabled: false },
  container: { docker_host: '-', workdir_parent: 'workspace' },
  host: { workdir_parent: '/workspace' },
});
local jobLabels = { app: 'forgejo-keda-runner', 'app.kubernetes.io/managed-by': 'forgejo-keda' };
local jobSelector = jobLabels { 'k8s:io.kubernetes.pod.namespace': jobNamespace };
local forgejoSelector = { 'k8s:io.kubernetes.pod.namespace': namespace, app: 'forgejo' };
local sandbox =
  container.securityContext.withAllowPrivilegeEscalation(false)
  + container.securityContext.capabilities.withDrop(['ALL']);

local runnerPod(arch) =
  pod.metadata.withLabels(jobLabels)
  + pod.metadata.withAnnotations({ 'checksum/config': std.md5(runnerConfig(arch)) })
  + pod.spec.withRuntimeClassName('gvisor')  // Shared RuntimeClass is owned by envs/network
  + pod.spec.withNodeSelector({ 'kubernetes.io/arch': arch })
  + pod.spec.withRestartPolicy('Never')
  + pod.spec.withAutomountServiceAccountToken(false)
  + pod.spec.withServiceAccountName('default')
  + pod.spec.withEnableServiceLinks(false)
  + pod.spec.withTerminationGracePeriodSeconds(60)
  + pod.spec.securityContext.seccompProfile.withType('RuntimeDefault')
  + pod.spec.withVolumes([
    volume.fromEmptyDir('runner-bin') + volume.emptyDir.withSizeLimit('256Mi'),
    volume.fromEmptyDir('docker-bin') + volume.emptyDir.withSizeLimit('128Mi'),
    volume.fromEmptyDir('runner-config') + volume.emptyDir.withSizeLimit('1Mi'),
    volume.fromEmptyDir('workspace') + volume.emptyDir.withSizeLimit('2Gi'),
    volume.fromEmptyDir('home') + volume.emptyDir.withSizeLimit('512Mi'),
    volume.fromEmptyDir('tmp') + volume.emptyDir.withSizeLimit('512Mi'),
    volume.fromConfigMap(configName(arch), configName(arch)),
  ])
  + pod.spec.withInitContainers([
    // Both official binaries are static; reuse them in the Node toolbox without a custom image
    container.new('runner-binaries', runnerImage)
    + sandbox
    + container.withCommand(['sh', '-ec', 'cp /bin/forgejo-runner /usr/bin/dumb-init /runner-bin/'])
    + container.withVolumeMounts([volumeMount.new('runner-bin', '/runner-bin')])
    + container.withEnvMap({ TZ: timezone }),

    // Standard Docker actions need the CLI, not a daemon; remote BuildKit still does the builds
    container.new('docker-cli', 'docker:29-cli')
    + sandbox
    + container.withCommand(['sh', '-ec', 'cp /usr/local/bin/docker /docker-bin/docker'])
    + container.withVolumeMounts([volumeMount.new('docker-bin', '/docker-bin')])
    + container.withEnvMap({ TZ: timezone }),

    // Same image USER as the worker so its private .runner file remains readable without extra capabilities.
    // Only this init sees the reusable registration token; stock Runner saves fresh ephemeral credentials.
    container.new('register', jobImage)
    + sandbox
    + container.withCommand(['sh', '-ec', |||
      : "${REGISTRATION_TOKEN:?registration token is missing}"
      exec /runner-bin/forgejo-runner --config /config/config.yaml register \
        --no-interactive --ephemeral --instance "$FORGEJO_URL" \
        --name "$POD_NAME" --labels "$RUNNER_LABELS" --token "$REGISTRATION_TOKEN"
    |||])
    + container.withVolumeMounts([
      volumeMount.new('runner-bin', '/runner-bin', true),
      volumeMount.new(configName(arch), '/config', true),
      volumeMount.new('runner-config', '/runner-config'),
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
    container.new('runner', jobImage)
    + sandbox
    + container.withCommand([
      '/runner-bin/dumb-init',
      '--',
      '/runner-bin/forgejo-runner',
      '--config',
      '/config/config.yaml',
      'one-job',
      '--wait',
    ])
    + container.withWorkingDir('/workspace')
    + container.withVolumeMounts([
      volumeMount.new('runner-bin', '/runner-bin', true),
      volumeMount.new('runner-config', '/runner-config', true),
      volumeMount.new('docker-bin', '/docker-bin', true),
      volumeMount.new(configName(arch), '/config', true),
      volumeMount.new('workspace', '/workspace'),
      volumeMount.new('home', '/home/runner'),
      volumeMount.new('tmp', '/tmp'),
    ])
    + container.resources.withRequests({ cpu: '100m', memory: '128Mi', 'ephemeral-storage': '256Mi' })
    + container.resources.withLimits({ cpu: '2', memory: '2Gi', 'ephemeral-storage': '4Gi' })
    + container.withEnvMap({
      HOME: '/home/runner',
      PATH: '/docker-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      TZ: timezone,
    }),
  ]);

{
  nativeJobNamespace:
    k.core.v1.namespace.new(jobNamespace)
    // Image USER (including root) is honored; admission requires gVisor and drops capabilities
    + k.core.v1.namespace.metadata.withLabels({
      'pod-security.kubernetes.io/enforce': 'baseline',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    }),

  // Retain the quota identity; cap six non-terminal Pods (KEDA counts its minimum separately)
  nativeJobQuota:
    k.core.v1.resourceQuota.new('forgejo-native-canary')
    + k.core.v1.resourceQuota.metadata.withNamespace(jobNamespace)
    + k.core.v1.resourceQuota.spec.withHard({ pods: '6' }),

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
          // Absolute lifetime including idle time: bounds malicious runners, but can cut a late-starting job short
          activeDeadlineSeconds: 6 * 60 * 60,
          template: runnerPod(arch),
        },
        triggers: [{
          type: 'forgejo-runner',
          metadata: {
            address: forgejoURL,
            global: 'true',
            // Generic jobs can match either pool; reconciliation is not an instantaneous idle guarantee
            labels: 'k8s,k8s-' + arch,
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
      {
        toEndpoints: [{ matchLabels: forgejoSelector }],
        toPorts: [{ ports: [{ port: '80', protocol: 'TCP' }] }],
      },
      // The registry's VPN hostname resolves to Traefik inside the cluster, not to world
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'traefik', 'app.kubernetes.io/name': 'traefik' } }],
        toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }], serverNames: ['git.vpn.dzerv.art'] }],
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
    }]),

  nativeJobForgejoIngress:
    ciliumNetworkPolicy.new('forgejo-runners')
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({ app: 'forgejo' })
    + ciliumNetworkPolicy.spec.withIngress([{
      fromEndpoints: [
        { matchLabels: jobSelector },
        { matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'keda', 'app.kubernetes.io/name': 'keda-operator' } },
      ],
      toPorts: [{ ports: [{ port: '80', protocol: 'TCP' }] }],
    }]),

  // No Actions cache-signing key is exposed to host-mode jobs. Their runner config disables that cache.
  // TODO: Provision the isolated remote BuildKit workers used by .forgejo/workflows/docker.yaml
} + jobPolicy(jobNamespace)
