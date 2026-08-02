local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'netmaker';
local domain = 'vpn.dzerv.art';
local operatorName = 'netmaker-k8s-ops';
local secretKeyRef(name, key) = { valueFrom: { secretKeyRef: { name: name, key: key } } };
local secretEnv(name, secretName, key) = { name: name } + secretKeyRef(secretName, key);

local patchContainerEnv(workload, containerName, env) = workload {
  spec+: {
    template+: {
      spec+: {
        containers: std.map(
          function(container)
            if container.name == containerName then container { env+: env }
            else container,
          workload.spec.template.spec.containers
        ),
      },
    },
  },
};

local patchContainerEnvValue(workload, containerName, envName, valueFrom) = workload {
  spec+: {
    template+: {
      spec+: {
        containers: std.map(
          function(container)
            if container.name == containerName then container {
              env: std.map(
                function(item)
                  if item.name == envName then { name: envName, valueFrom: valueFrom }
                  else item,
                container.env
              ),
            }
            else container,
          workload.spec.template.spec.containers
        ),
      },
    },
  },
};

local withAffinity(workload, podLabels) = workload {
  spec+: {
    template+: {
      spec+: {
        affinity: affinity.combine([
          affinity.avoidHomelab,
          affinity.spreadAcrossNodes(podLabels),
        ]),
      },
    },
  },
};

local externalSecret(name, targetName, properties) = {
  apiVersion: 'external-secrets.io/v1',
  kind: 'ExternalSecret',
  metadata: { name: name, namespace: namespace },
  spec: {
    refreshInterval: '1h',
    secretStoreRef: { kind: 'ClusterSecretStore', name: '1password' },
    target: { name: targetName, creationPolicy: 'Owner' },
    data: std.map(
      function(property) {
        secretKey: property.secretKey,
        remoteRef: { key: 'netmaker', property: property.property },
      },
      properties
    ),
  },
};

local netmaker = helm.template('netmaker', '../../charts/netmaker', {
  namespace: namespace,
  values: {
    baseDomain: domain,
    fullnameOverride: 'netmaker',

    // The chart is the upstream OSS HA chart. EE values are deliberately empty.
    server: {
      replicas: 2,
      masterKey: 'overridden-by-netmaker-secrets',
      frontendURL: 'https://' + domain,
      ee: { licensekey: '', tenantId: '' },
    },
    ui: { replicas: 2 },
    mq: {
      replicas: 1,  // The upstream chart explicitly rejects more than one MQTT replica.
      username: 'netmaker',
      password: 'overridden-by-netmaker-secrets',
    },

    // CloudNativePG owns PostgreSQL. The chart's single-instance database is disabled.
    postgres: { enabled: false },
    db: {
      type: 'postgres',
      sslmode: 'require',
      existingSecret: {
        enabled: true,
        name: 'netmaker-postgres',
        keys: {
          host: 'host',
          port: 'port',
          username: 'user',
          password: 'password',
          database: 'dbname',
        },
      },
    },

    dns: { enabled: false },
    certManager: { enabled: false },
    ingress: {
      enabled: false,
      hostPrefix: {
        ui: 'dashboard',
        rest: 'api',
        broker: 'broker',
      },
    },
    gateway: {
      enabled: true,
      parentRefs: [{
        name: 'traefik-gateway',
        namespace: 'traefik',
        sectionName: 'websecure',
      }],
    },
  },
});

local operator = helm.template(operatorName, '../../charts/netmaker-k8s-ops', {
  namespace: namespace,
  values: {
    fullnameOverride: operatorName,
    namespace: { create: false, name: namespace },
    image: { repository: 'gravitl/netmaker-k8s-ops', tag: '1.4.0' },
    replicaCount: 1,
    manager: {
      configMap: {
        proxyMode: 'noauth',  // Netmaker Pro user sync is intentionally disabled.
        proxySkipTLSVerify: 'false',
      },
    },
    api: { enabled: false, serverDomain: '', token: '' },
    rbac: { create: true, useBroadPermissions: false },
    webhook: { enabled: false },
    service: {
      webhook: { enabled: false },
      metrics: { enabled: false },
      proxy: { enabled: true },
    },
    netclient: {
      // A non-empty value makes the chart add TOKEN_FROM_SECRET to the sidecar.
      // The rendered placeholder Secret is hidden below and replaced by ExternalSecret.
      token: 'external-secret',
    },
    volumes: {
      netclientConfig: {
        usePVC: true,
        storageSize: '1Gi',
        storageClassName: 'longhorn-stable',
        accessModes: ['ReadWriteOnce'],
      },
    },
  },
});

{
  namespace: k.core.v1.namespace.new(namespace),

  // 1Password item `netmaker`: master-key and mq-password are random secrets;
  // admin-token and restricted-token are enrollment tokens created after the
  // two OSS trust-tier networks have been bootstrapped (see README.md).
  serverSecrets: externalSecret('netmaker-secrets', 'netmaker-secrets', [
    { secretKey: 'master-key', property: 'master-key' },
    { secretKey: 'mq-password', property: 'mq-password' },
  ]),
  adminToken: externalSecret('netmaker-admin-token', 'netclient-token', [
    { secretKey: 'token', property: 'admin-token' },
  ]),
  restrictedToken: externalSecret('netmaker-restricted-token', 'netclient-token-restricted', [
    { secretKey: 'token', property: 'restricted-token' },
  ]),

  netmaker:
    netmaker
    + {
      // The chart only supports DB credentials through an existing Secret.
      // Override its ConfigMap placeholders for the other secrets at container level.
      stateful_set_netmaker:
        withAffinity(
          patchContainerEnv(netmaker.stateful_set_netmaker, 'netmaker', [
            secretEnv('MASTER_KEY', 'netmaker-secrets', 'master-key'),
            secretEnv('MQ_PASSWORD', 'netmaker-secrets', 'mq-password'),
          ]),
          { app: 'netmaker' }
        ),

      deployment_netmaker_mqtt:
        withAffinity(
          patchContainerEnvValue(
            netmaker.deployment_netmaker_mqtt,
            'mosquitto',
            'MQ_PASSWORD',
            { secretKeyRef: { name: 'netmaker-secrets', key: 'mq-password' } }
          ),
          { app: 'netmaker-mqtt' }
        ),

      deployment_netmaker_ui:
        withAffinity(netmaker.deployment_netmaker_ui, { app: 'netmaker-ui' }),

      // vpn.dzerv.art is the human entry point. API and broker remain at
      // api.vpn.dzerv.art and broker.vpn.dzerv.art, as required by Netmaker.
      http_route_netmaker_dashboard:
        netmaker.http_route_netmaker_dashboard {
          spec+: { hostnames: [domain] },
        },

      // Helm tests must not become permanently managed Pods in Tanka.
      pod_netmaker_test_connection:: netmaker.pod_netmaker_test_connection,
    },

  operator:
    operator
    + {
      deployment_netmaker_k_8s_ops:
        withAffinity(
          operator.deployment_netmaker_k_8s_ops,
          { 'app.kubernetes.io/name': 'netmaker-k8s-ops' }
        ),

      // Replaced by the `adminToken` ExternalSecret above.
      secret_netclient_token:: operator.secret_netclient_token,
      pod_netmaker_k_8s_ops_test_connection:: operator.pod_netmaker_k_8s_ops_test_connection,
    },

  serverPdb: {
    apiVersion: 'policy/v1',
    kind: 'PodDisruptionBudget',
    metadata: { name: 'netmaker', namespace: namespace },
    spec: { minAvailable: 1, selector: { matchLabels: { app: 'netmaker' } } },
  },
  uiPdb: {
    apiVersion: 'policy/v1',
    kind: 'PodDisruptionBudget',
    metadata: { name: 'netmaker-ui', namespace: namespace },
    spec: { minAvailable: 1, selector: { matchLabels: { app: 'netmaker-ui' } } },
  },

  // One operator can create ingress proxies with different enrollment-token
  // Secrets. This is the OSS replacement for Pro user/group ACLs.
  adminIngress: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'netmaker-admin-ingress',
      namespace: 'traefik',
      annotations: {
        'netmaker.io/ingress': 'enabled',
        'netmaker.io/secret-name': 'netclient-token',
        'netmaker.io/secret-key': 'token',
      },
    },
    spec: {
      type: 'ClusterIP',
      selector: { 'app.kubernetes.io/name': 'traefik' },
      ports: [{ name: 'https', port: 443, targetPort: 'websecure', protocol: 'TCP' }],
    },
  },

  kubeApiIngress: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'netmaker-kube-api-ingress',
      namespace: 'default',
      annotations: {
        'netmaker.io/ingress': 'enabled',
        'netmaker.io/secret-name': 'netclient-token',
        'netmaker.io/secret-key': 'token',
        'netmaker.io/ingress-dns-name': 'kube.' + domain,
      },
    },
    spec: {
      type: 'ExternalName',
      externalName: 'kubernetes.default.svc.cluster.local',
      ports: [{ name: 'https', port: 443, targetPort: 443, protocol: 'TCP' }],
    },
  },

  restrictedIngress: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'netmaker-cliproxyapi-ingress',
      namespace: 'cliproxyapi',
      annotations: {
        'netmaker.io/ingress': 'enabled',
        'netmaker.io/secret-name': 'netclient-token-restricted',
        'netmaker.io/secret-key': 'token',
        'netmaker.io/ingress-dns-name': 'ai.' + domain,
      },
    },
    spec: {
      type: 'ClusterIP',
      selector: { 'app.kubernetes.io/name': 'cliproxyapi' },
      ports: [{ name: 'http', port: 8317, targetPort: 8317, protocol: 'TCP' }],
    },
  },
}
