local externalSecrets = import 'external-secrets-libsonnet/1.1/main.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local gateways = import './gateways.libsonnet';
local postgres = import '../cloudnative-pg/cluster.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local podDisruptionBudget = k.policy.v1.podDisruptionBudget;
local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

local namespace = 'netmaker';
local domain = 'vpn.dzerv.art';
local dashboardDomain = 'dashboard.' + domain;
local operatorName = 'netmaker-k8s-ops';

local secretEnv(name, secretName, key) = {
  name: name,
  valueFrom: { secretKeyRef: { name: secretName, key: key } },
};

local patchContainer(workload, containerName, patch) = workload {
  spec+: {
    template+: {
      spec+: {
        containers: std.map(
          function(container)
            if container.name == containerName then container + patch(container)
            else container,
          workload.spec.template.spec.containers
        ),
      },
    },
  },
};

local appendContainerEnv(workload, containerName, env) =
  patchContainer(workload, containerName, function(_) { env+: env });

local redirectContainerEnv(workload, containerName, envName, secretName, secretKey) =
  patchContainer(workload, containerName, function(container) {
    env: std.map(
      function(item)
        if item.name == envName then secretEnv(envName, secretName, secretKey)
        else item,
      container.env
    ),
  });

local setContainerEnv(workload, containerName, envName, value) =
  patchContainer(workload, containerName, function(container) {
    env: std.map(
      function(item)
        if item.name == envName then { name: envName, value: value }
        else item,
      container.env
    ),
  });

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

local ingressAnnotations(secretKey, dnsName=null) = {
  'netmaker.io/ingress': 'enabled',
  'netmaker.io/secret-name': 'netmaker-op',
  'netmaker.io/secret-key': secretKey,
} + if dnsName == null then {} else { 'netmaker.io/ingress-dns-name': dnsName };

local proxyService(name, serviceNamespace, selector, port, targetPort, secretKey, dnsName=null, portName='https') =
  service.new(name, selector, [servicePort.newNamed(portName, port, targetPort)])
  + service.metadata.withNamespace(serviceNamespace)
  + service.metadata.withAnnotations(ingressAnnotations(secretKey, dnsName));

local pdb(name, labels) =
  podDisruptionBudget.new(name)
  + podDisruptionBudget.metadata.withNamespace(namespace)
  + podDisruptionBudget.spec.withMinAvailable(1)
  + podDisruptionBudget.spec.selector.withMatchLabels(labels);

local netmaker = helm.template('netmaker', '../../charts/netmaker', {
  namespace: namespace,
  values: {
    baseDomain: domain,
    fullnameOverride: 'netmaker',
    server: {
      replicas: 2,
      image: {
        repository: 'ghcr.io/dzervas/netmaker',
        tag: 'latest',
      },
      masterKey: 'external-secret',
      frontendURL: 'https://' + dashboardDomain,
      ee: { licensekey: '', tenantId: '' },
      RWX: { storageClassName: 'longhorn' },
    },
    ui: { replicas: 1 },
    mq: {
      // The official chart rejects mq.replicas > 1.
      replicas: 1,
      username: 'netmaker',
      password: 'external-secret',
    },
    postgres: { enabled: false },
    db: {
      type: 'postgres',
      sslmode: 'require',
      existingSecret: {
        enabled: true,
        name: 'netmaker-db-app',
        keys: {
          host: 'host',
          port: 'port',
          username: 'user',
          password: 'password',
          database: 'dbname',
        },
      },
    },
    dns: {
      enabled: true,
      RWX: { storageClassName: 'longhorn' },
    },
    certManager: { enabled: false },
    ingress: {
      enabled: false,
      hostPrefix: { ui: 'dashboard', rest: 'api', broker: 'broker' },
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
    image: { repository: 'gravitl/netmaker-k8s-ops', tag: 'latest' },
    nodeSelector: { 'kubernetes.io/arch': 'amd64' },  // Only amd64 image available
    replicaCount: 1,
    manager: {
      configMap: {
        proxyMode: 'noauth',
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
    netclient: { token: 'external-secret' },
    volumes: {
      netclientConfig: {
        usePVC: true,
        storageSize: '1Gi',
        accessModes: ['ReadWriteMany'],
      },
    },
  },
});

{
  namespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({ ghcrCreds: 'enabled' }),

  // One 1Password item and one Kubernetes Secret hold all Netmaker credentials.
  opSecret:
    externalSecret.new('netmaker-op')
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'netmaker' } }])
    + externalSecret.spec.target.withCreationPolicy('Owner'),

  netmaker:
    netmaker
    {
      stateful_set_netmaker:
        withAffinity(
          appendContainerEnv(netmaker.stateful_set_netmaker, 'netmaker', [
            secretEnv('MASTER_KEY', 'netmaker-op', 'master-key'),
            secretEnv('MQ_PASSWORD', 'netmaker-op', 'mq-password'),
          ]),
          { app: 'netmaker' }
        )
        + { spec+: { template+: { spec+: { imagePullSecrets: [{ name: 'ghcr-cluster-secret' }] } } } },

      // The chart mounts the shared RWX DNS volume into coredns, whose distroless
      // image runs as UID 65532, but Netmaker writes the Corefile as root and a
      // Longhorn RWX export root is `drwx------ root root`. `fsGroup` cannot fix
      // this: Longhorn's CSIDriver uses the default `ReadWriteOnceWithFSType`
      // fsGroupPolicy, so Kubernetes skips ownership management on RWX volumes.
      // share-manager does not squash root, so root in the pod can read it.
      deployment_netmaker_coredns:
        patchContainer(
          netmaker.deployment_netmaker_coredns,
          'netmaker-dns',
          function(_) { securityContext+: { runAsUser: 0, runAsGroup: 0 } }
        ),
      deployment_netmaker_mqtt:
        withAffinity(
          redirectContainerEnv(
            netmaker.deployment_netmaker_mqtt,
            'mosquitto',
            'MQ_PASSWORD',
            'netmaker-op',
            'mq-password'
          ),
          { app: 'netmaker-mqtt' }
        ),

      // Dashboard is reachable through the public listener only from VPN sources.
      http_route_netmaker_dashboard:
        netmaker.http_route_netmaker_dashboard {
          spec+: {
            rules: std.map(
              function(rule) rule {
                filters+: [{
                  type: 'ExtensionRef',
                  extensionRef: {
                    group: 'traefik.io',
                    kind: 'Middleware',
                    name: 'netmaker-dashboard',
                  },
                }],
              },
              netmaker.http_route_netmaker_dashboard.spec.rules
            ),
          },
        },

      pod_netmaker_test_connection:: netmaker.pod_netmaker_test_connection,
    },

  dashboardMiddleware: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: 'netmaker-dashboard', namespace: namespace },
    spec: {
      chain: { middlewares: [{ name: 'vpnonly', namespace: 'traefik' }] },
    },
  },

  operator:
    operator
    {
      // OPERATOR_NAMESPACE has no chart value and the binary defaults it to
      // `netmaker-k8s-ops-system`. The ingress controller resolves a Service's
      // `netmaker.io/secret-name` in the Service's own namespace first, then
      // falls back to OPERATOR_NAMESPACE; our proxy Services live in traefik,
      // cliproxyapi and default while `netmaker-op` lives here, so without this
      // both lookups miss and every proxy pod gets TOKEN="" and fails to enroll.
      deployment_netmaker_k_8s_ops:
        withAffinity(
          appendContainerEnv(
            redirectContainerEnv(
              operator.deployment_netmaker_k_8s_ops,
              'netclient',
              'TOKEN',
              'netmaker-op',
              'enrollment-token'
            ),
            'manager',
            [{
              name: 'OPERATOR_NAMESPACE',
              valueFrom: { fieldRef: { fieldPath: 'metadata.namespace' } },
            }]
          ),
          { 'app.kubernetes.io/name': operatorName }
        ),

      // The chart's minimal ClusterRole omits Secrets, but the operator watches
      // them cluster-wide to resolve the `netmaker.io/secret-name` annotation on
      // ingress proxy Services. Without this it crash-loops on a Secret watch.
      cluster_role_netmaker_k_8s_ops_role:
        operator.cluster_role_netmaker_k_8s_ops_role {
          rules+: [{
            apiGroups: [''],
            resources: ['secrets'],
            verbs: ['get', 'list', 'watch'],
          }],
        },
      secret_netclient_token:: operator.secret_netclient_token,
      pod_netmaker_k_8s_ops_test_connection:: operator.pod_netmaker_k_8s_ops_test_connection,
    },

  serverPdb: pdb('netmaker', { app: 'netmaker' }),
  uiPdb: pdb('netmaker-ui', { app: 'netmaker-ui' }),

  adminIngress:
    proxyService(
      'netmaker-admin-ingress',
      'traefik',
      { 'app.kubernetes.io/name': 'traefik' },
      443,
      'websecure',
      'enrollment-token'
    ),

  restrictedIngress:
    proxyService(
      'netmaker-cliproxyapi-ingress',
      'cliproxyapi',
      { 'app.kubernetes.io/name': 'cliproxyapi' },
      8317,
      8317,
      'enrollment-token',
      'ai.' + domain,
      'http'
    ),

  kubeApiIngress:
    service.new('netmaker-kube-api-ingress', {}, [servicePort.newNamed('https', 443, 443)])
    + service.metadata.withNamespace('default')
    + service.metadata.withAnnotations(ingressAnnotations('enrollment-token', 'kube.' + domain))
    + service.spec.withType('ExternalName')
    + {
      spec+: {
        selector:: {},
        externalName: 'kubernetes.default.svc.cluster.local',
      },
    },

  // CNPG creates the `netmaker-db` database and owner, plus a `netmaker-db-app`
  // Secret containing connection details for the application.
  netmakerCluster: postgres.new('netmaker-db', 'netmaker', '2Gi'),
}  //+ gateways
