local externalSecrets = import 'external-secrets.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;

local runnerImage = 'data.forgejo.org/forgejo/runner:13';
local secretName = 'forgejo-runner';
local secretPath = '/run/secrets/forgejo-runner';
local dockerSocket = 'unix:///run/dind/docker.sock';
local cachePort = 4001;

// Offline registration secret = 16 hex identifier + 24 hex secret. The
// identifier is not confidential, so it's fixed here and the runner UUID
// (the ASCII bytes of the identifier as a UUID, see uuidFromSecret in
// forgejo-runner) can be derived at build time.
local runnerId = 'c0ffee00f0f9e7a1';
local runnerUuid =
  local h = std.join('', [std.format('%02x', c) for c in std.encodeUTF8(runnerId)]);
  std.join('-', [h[0:8], h[8:12], h[12:16], h[16:20], h[20:32]]);

local runnerConfig = std.manifestYamlDoc({
  runner: {
    labels: [
      'docker:docker://data.forgejo.org/oci/node:lts-trixie',
      'ubuntu-latest:docker://data.forgejo.org/oci/node:lts-trixie',
    ],
  },
  // Shared cache server so both replicas see the same caches. Caches are
  // scoped per repository and expire after 7 days unused / 30 days total
  // (hardcoded in act/artifactcache).
  cache: {
    enabled: true,
    external_server: 'http://forgejo-runner-cache:%d/' % cachePort,
    secret_url: 'file:%s/cache-secret' % secretPath,
  },
  // Bind-mount the dind socket into jobs at /var/run/docker.sock (docker
  // builds, buildx). The path is resolved by dockerd, which shares /run/dind.
  container: {
    docker_host: dockerSocket,
  },
  server: {
    connections: {
      forgejo: {
        url: 'http://forgejo/',
        uuid: runnerUuid,
        token_url: 'file:%s/token' % secretPath,
      },
    },
  },
});

{
  forgejoRunnerSecret:
    externalSecret.new(secretName)
    + externalSecret.spec.target.template.withData({
      token: runnerId + '{{ .password | sha1sum | trunc 24 }}',
      'cache-secret': '{{ .password | sha256sum }}',
    })
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'password',
        },
      },
    }]),

  forgejoRunnerConfig: k.core.v1.configMap.new('forgejo-runner-config', { 'config.yml': runnerConfig }),

  // Runner + dockerd sidecar, isolated by sysbox instead of privileged mode.
  // TODO: Could become a KEDA ScaledJob (forgejo-runner scaler + `forgejo-runner
  // one-job`) for per-job pods/dockerd and scale-to-zero, at the cost of cold
  // starts (fresh dockerd + image pulls per job).
  // The runner keeps labsonnet's non-root defaults; only dockerd runs as root,
  // and that root is confined to the pod's user namespace.
  forgejoRunner:
    lab.new('forgejo-runner', runnerImage)
    + lab.withNamespace('forgejo')
    + lab.withReplicas(2)
    + lab.withPort({ port: 8080 })  // Shim since it's required
    + lab.withEnv({
      TZ: timezone,
      DOCKER_HOST: dockerSocket,
      DOCKER_TLS_CERTDIR: '',
    })
    + lab.withEmptyDir('/run/dind')
    + lab.withEmptyDir('/data')
    + lab.withConfigMapMount('/config', 'forgejo-runner-config')
    + lab.withSecretMount(secretPath, secretName)
    + lab.withArgs(['bash', '-c', |||
      until [ -S /run/dind/docker.sock ]; do echo 'waiting for dockerd...'; sleep 1; done
      exec forgejo-runner daemon --config /config/config.yml
    |||])
    + lab.withContainer(
      container.new('dind', 'docker:29-dind')
      // Socket group = runner's GID so the non-root runner can use it
      + container.withArgs(['dockerd', '--host=' + dockerSocket, '--group=1000'])
    )
    + lab.withPodAnnotations({ 'checksum/config': std.md5(runnerConfig) })
    // Jobs egress via the pod IP (dind NAT), so this covers them too
    + lab.withPodLabels({ 'ai/enable': 'true' })  // see envs/cliproxyapi networkPolicy
    + {
      workload+:
        deployment.spec.template.spec.withRuntimeClassName('sysbox-runc')
        + { spec+: { template+: { spec+: { hostUsers: false } } } }
        // labsonnet applies one securityContext to every container; replace
        // (not merge) it for dockerd so it keeps its default capabilities.
        + deployment.mapContainers(function(c)
          if c.name == 'dind' then c {
            securityContext: {
              runAsNonRoot: false,
              runAsUser: 0,
              runAsGroup: 0,
            },
          } else c),
    },

  forgejoRunnerCache:
    lab.new('forgejo-runner-cache', runnerImage)
    + lab.withNamespace('forgejo')
    + lab.withType('StatefulSet')
    + lab.withPort({ port: cachePort, name: 'http' })
    + lab.withPV('/data', { name: 'data', size: '20Gi', storageClassName: 'longhorn-throwaway' })
    + lab.withEnv({ TZ: timezone })
    + lab.withSecretEnv({ CACHE_SECRET: { name: secretName, key: 'cache-secret' } })
    + lab.withArgs([
      'forgejo-runner',
      'cache-server',
      '--dir=/data',
      '--port=%d' % cachePort,
      '--secret=$(CACHE_SECRET)',
    ]),
}
