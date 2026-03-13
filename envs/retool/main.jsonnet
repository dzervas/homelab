local externalSecrets = import 'external-secrets-libsonnet/1.1/main.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local labsonnet = import 'labsonnet/main.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local podAffinityTerm = k.core.v1.podAffinityTerm;

local helm = tk.helm.new(std.thisFile);

local deployment = k.apps.v1.deployment;
local namespace = 'retool';
local domain = 'retool.vpn.dzerv.art';
local retoolVersion = '3.334.0';

local colocateWithPgdb = deployment.spec.template.spec.affinity.podAffinity.withRequiredDuringSchedulingIgnoredDuringExecution([{
  labelSelector: {
    matchLabels: {
      'app.kubernetes.io/instance': 'retool',
      'app.kubernetes.io/name': 'postgresql',
    },
  },
  topologyKey: 'provider',
}]);

local retoolHelmDef = helm.template('retool', '../../charts/retool', {
  namespace: namespace,
  values: {
    image: {
      repository: 'ghcr.io/dzervas/retool',
      pullSecrets: [{ name: 'ghcr-cluster-secret' }],
      pullPolicy: 'Always',
      tag: 'latest',
    },

    persistentVolumeClaim: {
      enabled: true,
      storageClass: 'longhorn',
    },
    securityContext: {
      enabled: true,
      privileged: false,
      runAsUser: 999,  // retool-user
      runAsGroup: 999,
      runAsNonRoot: true,
    },

    podLabels: { 'ai/enable': 'true' },
    dbconnector: { java: { enabled: false } },

    config: {
      licenseKey: 'SSOP_LOCAL_ONLY',
      useInsecureCookies: false,

      // Secrets provided via ExternalSecret
      encryptionKeySecretName: 'retool-secrets',
      encryptionKeySecretKey: 'encryption-key',
      jwtSecretSecretName: 'retool-secrets',
      jwtSecretSecretKey: 'jwt-secret',

      postgresql: { username: 'retool' },

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
        existingSecret: 'retool-secrets',
        secretKeys: { userPasswordKey: 'postgres-password' },
      },
      primary: {
        // TODO: Remove once retool supports arm64
        nodeSelector: { 'kubernetes.io/arch': 'amd64' },
      },
    },

    ingress: ingress.hostObj(domain),

    // Enable local temporal cluster
    'retool-temporal-services-helm': {
      enabled: true,
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
                existingSecret: 'retool-secrets',
                secretKey: 'postgres-password',
              },
            },
            visibility: {
              sql: {
                host: 'retool-postgresql',
                port: 5432,
                database: 'temporal_visibility',
                user: 'retool',
                existingSecret: 'retool-secrets',
                secretKey: 'postgres-password',
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
    // nodeSelector: { 'kubernetes.io/arch': null },

    service: {
      labels: { 'magicentry.rs/enable': 'true' },
      annotations: {
        'magicentry.rs/name': 'Retool',
        'magicentry.rs/url': 'https://retool.vpn.dzerv.art',
        'magicentry.rs/realms': 'retool',
        'magicentry.rs/oidc_redirect_urls': 'https://retool.vpn.dzerv.art/oauth2sso/callback',
      },
    },

    env: {
      CUSTOM_OAUTH2_SSO_SCOPES: 'openid email profile offline_access',
      CUSTOM_OAUTH2_SSO_AUTH_URL: 'https://auth.dzerv.art/oidc/authorize',
      CUSTOM_OAUTH2_SSO_TOKEN_URL: 'https://magicentry.magicentry.svc.cluster.local:8080/oidc/token',
      CUSTOM_OAUTH2_SSO_USERINFO_URL: 'https://magicentry.magicentry.svc.cluster.local:8080/oidc/userinfo',
      CUSTOM_OAUTH2_SSO_JWT_EMAIL_KEY: 'idToken.email',

      RETOOLDB_POSTGRES_HOST: 'retooldb-postgresql-hl',
      RETOOLDB_POSTGRES_PORT: '5432',
      RETOOLDB_POSTGRES_USER: 'retooldb',
      RETOOLDB_POSTGRES_DB: 'retooldb',

      TZ: timezone,
      BASE_DOMAIN: 'https://' + domain,
      CONTAINER_UNPRIVILEGED_MODE: 'true',
      DISABLE_IPTABLES_SECURITY_CONFIGURATION: 'true',
    },

    environmentSecrets: [
      { name: 'CUSTOM_OAUTH2_SSO_CLIENT_ID', secretKeyRef: { name: 'retool-magicentry', key: 'client_id' } },
      { name: 'CUSTOM_OAUTH2_SSO_CLIENT_SECRET', secretKeyRef: { name: 'retool-magicentry', key: 'client_secret' } },

      { name: 'RETOOLDB_POSTGRES_PASSWORD', secretKeyRef: { name: 'retool-secrets', key: 'retooldb-postgres-password' } },
    ],
  },
});

// Patch workflow pods only: chart uses postgres-password even when username is non-postgres.
// Keep vendored chart untouched by rewriting the env entry in rendered Deployments.
local fixWorkflowPostgresPasswordKey(obj) =
  obj { spec+: { template+: { spec+: { containers: std.map(
    function(c)
      c {
        env: std.map(
          function(e) if std.objectHas(e, 'name') && e.name == 'POSTGRES_PASSWORD' then e { valueFrom+: { secretKeyRef+: { name: 'retool-secrets', key: 'postgres-password' } } } else e,
          c.env
        ),
      },
    obj.spec.template.spec.containers
  ) } } } };

{
  namespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({ ghcrCreds: 'enabled' }),

  retool: retoolHelmDef {
    deployment_retool+: fixWorkflowPostgresPasswordKey(
      retoolHelmDef.deployment_retool
    ) + colocateWithPgdb,
    deployment_retool_agent_eval_worker+: fixWorkflowPostgresPasswordKey(
      retoolHelmDef.deployment_retool_agent_eval_worker
    ),
    deployment_retool_agent_worker+: fixWorkflowPostgresPasswordKey(
      retoolHelmDef.deployment_retool_agent_worker
    ),
    deployment_retool_workflow_backend+: fixWorkflowPostgresPasswordKey(
      retoolHelmDef.deployment_retool_workflow_backend
    ),
    deployment_retool_workflow_worker+: fixWorkflowPostgresPasswordKey(
      retoolHelmDef.deployment_retool_workflow_worker
    ),
    deployment_retool_code_executor+: deployment.spec.template.spec.withContainers(std.map(
      function(c) c + k.core.v1.container.withImage('tryretool/code-executor-service:latest'),
      retoolHelmDef.deployment_retool_code_executor.spec.template.spec.containers
    )),
  },

  retooldb: helm.template('retooldb', '../../charts/postgresql', {
    namespace: namespace,
    values: {
      image: {
        repository: 'postgres',
        tag: '16',
      },
      auth: {
        database: 'retooldb',
        username: 'retooldb',
        existingSecret: 'retool-secrets',
        secretKeys: { userPasswordKey: 'retooldb-postgres-password' },
      },
      global: { storageClass: 'longhorn' },

      primary: {
        podSecurityContext: { fsGroup: 999 },
        containerSecurityContext: { runAsUser: 999 },

        // TODO: Remove once retool supports arm64
        nodeSelector: { 'kubernetes.io/arch': 'amd64' },
      },
    },
  }),

  retoolSecrets:
    local newRandomTarget(name) = {
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'password',
        },
      },
      rewrite: [{ regexp: { source: 'password', target: name } }],
    };

    externalSecret.new('retool-secrets')
    + externalSecret.spec.withRefreshPolicy('CreatedOnce')
    + externalSecret.spec.withDataFrom([
      newRandomTarget('encryption_key'),
      newRandomTarget('jwt_secret'),
      newRandomTarget('postgres_password'),
      newRandomTarget('retooldb_postgres_password'),
    ])
    + externalSecret.spec.target.template.withData({
      'encryption-key': '{{ .encryption_key }}',
      'jwt-secret': '{{ .jwt_secret }}',
      'postgres-password': '{{ .postgres_password }}',
      'retooldb-postgres-password': '{{ .retooldb_postgres_password }}',
    }),

  server:
    labsonnet.new('retool-server', 'ghcr.io/dzervas/retool-server')
    + labsonnet.withPort({ port: 8000 })
    + labsonnet.withNamespace(namespace)
    + labsonnet.withImagePullSecrets(['ghcr-cluster-secret']),
}

// PostgreSQL initialization:
// k exec -it sts/retool-postgresql -it -- psql -U retool
// CREATE DATABASE temporal;
// CREATE DATABASE temporal_visibility;
// CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
//
// CREATE DATABASE retooldb;
// CREATE USER retooldb WITH PASSWORD 'password' CREATEDB CREATEROLE;
// ALTER DATABASE retooldb OWNER TO retooldb;
// GRANT ALL PRIVILEGES ON DATABASE retooldb TO retooldb;
