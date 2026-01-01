local dockerService = import 'docker-service.libsonnet';
local ingressLib = import 'docker-service/ingress.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local gemini = import 'helpers/gemini.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local p = import 'prometheus-operator-libsonnet/0.83/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local deployment = k.apps.v1.deployment;
local statefulset = k.apps.v1.statefulSet;
local container = k.core.v1.container;
local service = k.core.v1.service;

local namespace = 'plane';
local domain = 'projects.vpn.dzerv.art';
local prime_server = 'http://plane-prime.plane.svc.cluster.local:8000';

// Normalize Helm-rendered Jobs: detect names ending in "-YYYYMMDD-HHMMSS",
// strip the timestamp to make names/keys deterministic, and keep metadata in sync.
local normalizeJobNames(obj) =
  local isDigits(s) = std.foldl(function(acc, c) acc && c >= '0' && c <= '9', std.stringChars(s), true);
  local rebuild = function(acc, k)
    local v = obj[k] { spec+: { template+: { metadata+: { annotations+: { timestamp: null } } } } };
    if std.isObject(v) && v.kind == 'Job' && std.objectHas(v, 'metadata') && std.objectHas(v.metadata, 'name') then
      local parts = std.split(v.metadata.name, '-');
      local n = std.length(parts);
      local hasDateSuffix =
        n >= 2 &&
        std.length(parts[n - 2]) == 8 && isDigits(parts[n - 2]) &&
        std.length(parts[n - 1]) == 6 && isDigits(parts[n - 1]);
      local baseName = if hasDateSuffix then std.join('-', parts[0:n - 2]) else v.metadata.name;
      local newKey = 'job_' + baseName;
      acc {
        [newKey]: v {
          metadata+: { name: baseName },
        },
      }
    else
      acc { [k]: v };
  std.foldl(rebuild, std.objectFields(obj), {});

local planeHelmDef = std.prune(normalizeJobNames(
  helm.template('plane', '../../charts/plane-enterprise', {
    namespace: namespace,
    values: {
      license: {
        licenseDomain: domain,
        licenseServer: prime_server,
      },
      ingress: {
        enabled: true,
        ingressClass: 'vpn',
        ingress_annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt',
          'nginx.ingress.kubernetes.io/proxy-body-size': '5m',
        },

        appHost: domain,
      },
      ssl: {
        tls_secret_name: 'projects-vpn-dzerv-art-cert',
      },
      external_secrets: {
        silo_env_existingSecret: 'plane-silo-secrets',
      },
      env: {
        storageClass: 'openebs-replicated',  // This is incorrect but can't change now
      },
      services: {
        api: {
          cpuLimit: '2',  // Can't unset this
          cpuRequest: '500m',
          memoryLimit: '2Gi',
          memoryRequest: '500Mi',
        },
      },
      extraEnv: [
        { name: 'WEB_URL', value: 'https://' + domain },
        { name: 'PAYMENT_SERVER_BASE_URL', value: prime_server },
        { name: 'PAYMENT_SERVER_AUTH_TOKEN', value: 'hello_world' },
        { name: 'FEATURE_FLAG_SERVER_BASE_URL', value: prime_server },
        { name: 'FEATURE_FLAG_SERVER_AUTH_TOKEN', value: 'hello_world' },
        { name: 'PRIME_SERVER_BASE_URL', value: prime_server },
        { name: 'PRIME_SERVER_AUTH_TOKEN', value: 'hello_world' },
        { name: 'IS_AIRGAPPED', value: '1' },
        // { name: 'OPENAI_BASE_URL', value: 'https://api.z.ai/api/coding/paas/v4' },
        { name: 'TZ', value: timezone },
        // { name: 'GUNICORN_WORKERS', value: '4' },
      ],
    },
  })
));

{
  // NOTE: Creates the namespace
  planePrime: dockerService.new('plane-prime', 'ghcr.io/dzervas/plane-prime:latest', {
    namespace: namespace,
    ports: [8000],
  }),
  proxy: dockerService.new('proxy', 'ghcr.io/dzervas/netshoot', {
    namespace: namespace,
    ports: [8080, 8081],
    command: ['/bin/bash'],
    args: ['-c', 'mitmweb --set confdir=/tmp --web-host 0.0.0.0 --no-web-open-browser'],
  }),
  // Normalize job names so they stay stable across renders
  // Maybe migrate to rustfs instead of minio?
  plane: planeHelmDef {
    // Add the magicentry.rs/enable label to the plane-api-wl deployment
    // by patching the deployment template in the Helm output
    deployment_plane_api_wl+: deployment.spec.template.metadata.withLabelsMixin({ 'magicentry.rs/enable': 'true' }),
    // echo 'DATABASES["default"]["CONN_MAX_AGE"] = 600' >> plane/settings/common.py
    // echo 'DATABASES["default"]["CONN_HEALTH_CHECKS"] = True' >> plane/settings/common.py

    // metrics exposure
    // :9000/minio/v2/metrics/cluster
    // stateful_set_plane_minio_wl+: statefulset.spec.template.spec.withContainers(std.map(
    //   function(c)
    //     c + container.withEnvMixin([{ name: 'MINIO_PROMETHEUS_AUTH_TYPE', value: 'public' }]),
    //   planeHelmDef.stateful_set_plane_minio_wl.spec.template.spec.containers
    // )),
    // :15692/metrics
    service_plane_rabbitmq+:
      service.spec.withPortsMixin([{
        name: 'rabbitmq-metrics',
        port: 15692,
        targetPort: 15692,
        protocol: 'TCP',
      }]),
    // postgres statement stats
    stateful_set_plane_pgdb_wl+: statefulset.spec.template.spec.withContainers(std.map(
      function(c)
        c
        + container.resources.withLimits({
          cpu: '500m',
          memory: '2Gi',
        })
        + container.resources.withRequests({
          memory: '500Mi',
        }),
      // + container.withArgsMixin([
      //   '-c',
      //   'shared_preload_libraries=pg_stat_statements',
      //   '-c',
      //   'pg_stat_statements.track=all',
      //   '-c',
      //   'pg_stat_statements.max=10000',
      //   '-c',
      //   'track_io_timing=on',
      //   '-c',
      //   'log_min_duration_statement=500ms',
      //   '-c',
      //   'log_line_prefix=%m [%p] %u@%d %a %r',
      // ]),
      planeHelmDef.stateful_set_plane_pgdb_wl.spec.template.spec.containers
    )),
  },

  planeSecrets: {
    apiVersion: 'external-secrets.io/v1',
    kind: 'ExternalSecret',
    metadata: {
      name: 'plane-silo-secrets',
      namespace: namespace,
    },
    spec: {
      refreshPolicy: 'OnChange',
      target: {
        template: {
          data: {
            SILO_HMAC_SECRET_KEY: '{{ .password }}',
            // TODO: Change these
            DATABASE_URL: 'postgresql://plane:plane@plane-pgdb.plane.svc.cluster.local:5432/plane',
            REDIS_URL: 'redis://plane-redis.plane.svc.cluster.local:6379/',
            AMQP_URL: 'amqp://plane:plane@plane-rabbitmq.plane.svc.cluster.local/',
          },
        },
      },
      dataFrom: [{
        sourceRef: {
          generatorRef: {
            apiVersion: 'generators.external-secrets.io/v1alpha1',
            kind: 'ClusterGenerator',
            name: 'password',
          },
        },
      }],
    },
  },

  // Allow magicentry (auth namespace) to reach Plane pods
  planeMagicentryNetworkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'allow-plane-magicentry',
      namespace: namespace,
    },
    spec: {
      podSelector: {},
      policyTypes: ['Ingress'],
      ingress: [
        {
          from: [
            {
              namespaceSelector: {
                matchLabels: {
                  'kubernetes.io/metadata.name': 'auth',
                },
              },
              podSelector: {
                matchLabels: {
                  'app.kubernetes.io/name': 'magicentry',
                },
              },
            },
          ],
        },
      ],
    },
  },

  planeN8NNetworkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'allow-plane-n8n',
      namespace: namespace,
    },
    spec: {
      podSelector: {},
      policyTypes: ['Ingress'],
      ingress: [
        {
          from: [
            {
              namespaceSelector: {
                matchLabels: {
                  'kubernetes.io/metadata.name': 'n8n',
                },
              },
              podSelector: {
                matchLabels: {
                  service: 'n8n',
                },
              },
            },
          ],
        },
      ],
    },
  },

  // planeMinioMetrics:
  //   p.monitoring.v1.serviceMonitor.new('plane-minio')
  //   + p.monitoring.v1.serviceMonitor.spec.withJobLabel('plane-minio')
  //   + p.monitoring.v1.serviceMonitor.spec.withEndpoints([
  //     p.monitoring.v1.serviceMonitor.spec.endpoints.withPort('minio-api-9000')
  //     + p.monitoring.v1.serviceMonitor.spec.endpoints.withPath('/minio/v2/metrics/cluster'),
  //   ])
  //   + p.monitoring.v1.serviceMonitor.spec.selector.withMatchLabels({
  //     'app.name': 'plane-plane-minio',
  //   }),

  // planeRabbitMQMetrics:
  //   p.monitoring.v1.serviceMonitor.new('plane-rabbitmq')
  //   + p.monitoring.v1.serviceMonitor.spec.withJobLabel('plane-rabbitmq')
  //   + p.monitoring.v1.serviceMonitor.spec.withEndpoints([
  //     p.monitoring.v1.serviceMonitor.spec.endpoints.withPort('rabbitmq-metrics')
  //     + p.monitoring.v1.serviceMonitor.spec.endpoints.withPath('/metrics'),
  //   ])
  //   + p.monitoring.v1.serviceMonitor.spec.selector.withMatchLabels({
  //     'app.name': 'plane-plane-rabbitmq',
  //   }),


  // pgExporter: dockerService.new('plane-pgdb-exporter', 'quay.io/prometheuscommunity/postgres-exporter', {
  //   namespace: namespace,
  //   ports: [9187],
  //   args: [
  //     '--collector.postmaster',
  //     '--collector.process_idle',
  //     '--collector.stat_statements',
  //     '--collector.stat_wal_receiver',
  //   ],
  //   env: {
  //     DATA_SOURCE_URI: 'plane-pgdb.plane.svc.cluster.local:5432/plane?sslmode=disable',
  //     DATA_SOURCE_USER: 'plane',
  //     DATA_SOURCE_PASS: 'plane',
  //   },
  // }) + { namespace: null },
  // planePGMetrics:
  //   p.monitoring.v1.serviceMonitor.new('plane-pgdb-exporter')
  //   + p.monitoring.v1.serviceMonitor.spec.withJobLabel('plane-pgdb-exporter')
  //   + p.monitoring.v1.serviceMonitor.spec.withEndpoints([
  //     p.monitoring.v1.serviceMonitor.spec.endpoints.withPort('docker-9187')
  //     + p.monitoring.v1.serviceMonitor.spec.endpoints.withPath('/metrics'),
  //   ])
  //   + p.monitoring.v1.serviceMonitor.spec.selector.withMatchLabels({
  //     app: 'plane-pgdb-exporter',
  //   }),

  // Backup configurations for all Plane PVCs using the wrapper function
  planeBackups: gemini.backupMany(
    namespace=namespace,
    pvcClaimNames=[
      'pvc-plane-minio-vol-plane-minio-wl-0',
      'pvc-plane-monitor-vol-plane-monitor-wl-0',
      'pvc-plane-pgdb-vol-plane-pgdb-wl-0',
      'pvc-plane-rabbitmq-vol-plane-rabbitmq-wl-0',
      'pvc-plane-redis-vol-plane-redis-wl-0',
    ]
  ),
}
