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
local affinity = k.core.v1.affinity;
local podAffinityTerm = k.core.v1.podAffinityTerm;

// Pod affinity to colocate with PostgreSQL for low-latency communication
local colocateWithPgdb = deployment.spec.template.spec.affinity.podAffinity.withRequiredDuringSchedulingIgnoredDuringExecution([{
  labelSelector: {
    matchLabels: { 'app.name': 'plane-plane-pgdb' },
  },
  topologyKey: 'provider',
}]);

local namespace = 'plane';
local domain = 'projects.vpn.dzerv.art';
local prime_server = 'http://plane-prime:8000';

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
        rabbbitmq: {
          volumeSize: '1Gi',
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
        { name: 'LLM_BASE_URL', value: 'http://cliproxyapi.cliproxyapi.svc:8317/v1' },
        { name: 'LLM_API_KEY', value: 'sk-dummy' },
        { name: 'LLM_MODEL', value: 'glm-4.7-flash' },
        { name: 'TZ', value: timezone },
        // { name: 'IS_AIRGAPPED', value: '1' },
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
  }) + { workload+: colocateWithPgdb },
  // Normalize job names so they stay stable across renders
  // Maybe migrate to rustfs instead of minio?
  plane: planeHelmDef {
    // Increase gunicorn workers to prevent single-worker restart blocking all requests
    // (URL pattern compilation takes 3+ seconds on worker restart)
    config_map_plane_app_vars+: {
      data+: {
        GUNICORN_WORKERS: '4',
      },
    },

    // Add the magicentry.rs/enable label to the plane-api-wl deployment
    // by patching the deployment template in the Helm output
    // Also add pod affinity to colocate with PostgreSQL for low-latency
    // Manual patches before the exec entrypoint in the api:
    // echo -e '\n\nDATABASES["default"]["CONN_MAX_AGE"] = 600' >> plane/settings/common.py
    // echo 'DATABASES["default"]["CONN_HEALTH_CHECKS"] = True' >> plane/settings/common.py
    // sed -i 's/--max-requests 1200/--max-requests 0/' /code/bin/docker-entrypoint-api-ee.sh
    // sed -i 's/uvicorn.workers.UvicornWorker/sync/; s/plane.asgi:application/plane.wsgi:application/' /code/bin/docker-entrypoint-api-ee.sh
    // sed -i 's#OpenAI(api_key=LLM_API_KEY)#OpenAI(api_key=LLM_API_KEY, base_url="http://cliproxyapi.cliproxyapi.svc:8317/v1")#; s#OpenAI(api_key=api_key)#OpenAI(api_key=api_key, base_url="http://cliproxyapi.cliproxyapi.svc:8317/v1")#' plane/ee/views/app/ai/rephrase.py plane/app/views/external/base.py
    deployment_plane_api_wl+:
      colocateWithPgdb
      + deployment.spec.template.metadata.withLabelsMixin({
        'magicentry.rs/enable': 'true',
        'ai/enable': 'true',
      }),

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
        + container.resources.withRequests({ memory: '500Mi' })
        + container.resources.withLimits({
          cpu: '500m',
          memory: '2Gi',
        }),
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
            DATABASE_URL: 'postgresql://plane:plane@plane-pgdb:5432/plane',
            REDIS_URL: 'redis://plane-redis:6379/',
            AMQP_URL: 'amqp://plane:plane@plane-rabbitmq/',
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
