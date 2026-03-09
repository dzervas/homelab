local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local labsonnet = import 'labsonnet/main.libsonnet';

local helm = tk.helm.new(std.thisFile);

local namespace = 'retool';
local domain = 'retool.vpn.dzerv.art';

local retoolHelmDef = helm.template('retool', '../../charts/retool', {
  namespace: namespace,
  values: {
    image: {
      repository: 'ghcr.io/dzervas/retool',
      pullSecrets: [{ name: 'ghcr-cluster-secret' }],
      pullPolicy: 'Always',
      tag: 'latest',
    },

    persistentVolumeClaim: { enabled: true },

    deployment: { labels: { 'ai/enable': 'true' } },

    config: {
      licenseKey: 'EXPIRED-LICENSE-KEY-TRIAL',
      useInsecureCookies: false,
      // Secrets provided via ExternalSecret
      encryptionKeySecretName: 'retool-secrets',
      encryptionKeySecretKey: 'encryption-key',
      jwtSecretSecretName: 'retool-secrets',
      jwtSecretSecretKey: 'jwt-secret',
      // Disable Google auth
      auth: {
        google: {
          enabled: false,
        },
      },
    },

    // Use built-in PostgreSQL
    postgresql: {
      auth: {
        database: 'retool',
        username: 'retool',
        password: 'retool',
      },
    },

    ingress: ingress.hostObj(domain),

    // Enable local temporal cluster
    'retool-temporal-services-helm': {
      // enabled: true,
      // Temporal does not support arm64
      server: {
        nodeSelector: { 'kubernetes.io/arch': 'amd64' },
        config: {
          persistence: {
            default: {
              sql: {
                host: 'retool-postgresql',
                port: 5432,
                database: 'temporal',
                user: 'retool',
                password: 'retool',
              },
            },
            visibility: {
              sql: {
                host: 'retool-postgresql',
                port: 5432,
                database: 'temporal_visibility',
                user: 'retool',
                password: 'retool',
              },
            },
          },
        },
      },
    },

    // Disable external temporal (use local)
    temporal: { enabled: false },
    agents: { enabled: true },

    // Enable code executor for workflows
    codeExecutor: {
      resources: {
        limits: {
          cpu: '1000m',
          memory: '1024Mi',
        },
        requests: {
          cpu: '500m',
          memory: '512Mi',
        },
      },
      securityContext: {
        privileged: false,
        runAsUser: 1001,
        runAsGroup: 1001,
        runAsNonRoot: true,
      },
    },

    // Reduce resources for homelab
    resources: {
      limits: {
        cpu: '2000m',
        memory: '4096Mi',
      },
      requests: {
        cpu: '500m',
        memory: '1024Mi',
      },
    },

    replicaCount: 1,

    // Remove amd64 node selector constraint
    nodeSelector: {},

    env: {
      TZ: timezone,
      BASE_DOMAIN: domain,
      CONTAINER_UNPRIVILEGED_MODE: 'true',
    },
  },
});

// Patch workflow pods only: chart uses postgres-password even when username is non-postgres.
// Keep vendored chart untouched by rewriting the env entry in rendered Deployments.
local fixWorkflowPostgresPasswordKey(obj) =
  obj {
    spec+: {
      template+: {
        spec+: {
          containers: std.map(
            function(c)
              c {
                env: std.map(
                  function(e)
                    if std.objectHas(e, 'name') && e.name == 'POSTGRES_PASSWORD' then
                      e {
                        valueFrom+: {
                          secretKeyRef+: {
                            key: 'password',
                          },
                        },
                      }
                    else
                      e,
                  c.env
                ),
              },
            obj.spec.template.spec.containers
          ),
        },
      },
    },
  };

{
  namespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({ ghcrCreds: 'enabled' }),
  retool: retoolHelmDef {
    deployment_retool_workflow_backend+: fixWorkflowPostgresPasswordKey(
      retoolHelmDef.deployment_retool_workflow_backend
    ),
    deployment_retool_workflow_worker+: fixWorkflowPostgresPasswordKey(
      retoolHelmDef.deployment_retool_workflow_worker
    ),
  },

  retoolSecrets: {
    apiVersion: 'external-secrets.io/v1',
    kind: 'ExternalSecret',
    metadata: {
      name: 'retool-secrets',
      namespace: namespace,
    },
    spec: {
      refreshPolicy: 'OnChange',
      target: {
        template: {
          data: {
            'encryption-key': '{{ .encryption_key }}',
            'jwt-secret': '{{ .jwt_secret }}',
          },
        },
      },
      dataFrom: [
        {
          sourceRef: {
            generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: 'ClusterGenerator',
              name: 'password',
            },
          },
          rewrite: [{ regexp: { source: 'password', target: 'encryption_key' } }],
        },
        {
          sourceRef: {
            generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: 'ClusterGenerator',
              name: 'password',
            },
          },
          rewrite: [{ regexp: { source: 'password', target: 'jwt_secret' } }],
        },
      ],
    },
  },

  server:
    labsonnet.new('retool-server', 'ghcr.io/dzervas/retool-server')
    + labsonnet.withPort({ port: 8000 })
    + labsonnet.withNamespace(namespace)
    + labsonnet.withImagePullSecrets(['ghcr-cluster-secret']),
}
