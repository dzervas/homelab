local cm = import 'cert-manager-libsonnet/1.19/main.libsonnet';
local externalSecrets = import 'external-secrets.libsonnet';
local k = import 'k.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';

local certificate = cm.nogroup.v1.certificate;
local issuer = cm.nogroup.v1.issuer;
local password = externalSecrets.generators.v1alpha1.password;
local clusterSecretStore = externalSecrets.nogroup.v1.clusterSecretStore;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local serviceAccount = k.core.v1.serviceAccount;
local role = k.rbac.v1.role;
local roleBinding = k.rbac.v1.roleBinding;
local helm = tk.helm.new(std.thisFile);

local namespace = 'n8n-sandbox';
local authSecretName = 'n8n-sandbox-auth';
local authReaderName = 'n8n-sandbox-auth-reader';
local sandboxLabels = {
  'app.kubernetes.io/name': 'n8n-sandbox-service',
  'app.kubernetes.io/instance': 'sandbox',
};

{
  namespace: k.core.v1.namespace.new(namespace),

  runtimeClass: {
    apiVersion: 'node.k8s.io/v1',
    kind: 'RuntimeClass',
    metadata: {
      name: 'sysbox-runc',
      annotations: {
        'tanka.dev/namespaced': 'false',
      },
    },
    handler: 'sysbox-runc',
    scheduling: {
      nodeSelector: {
        'sysbox-runtime': 'running',
      },
    },
  },

  sandbox: helm.template('sandbox', '../../charts/n8n-sandbox-service', {
    namespace: namespace,
    values: {
      auth: {
        existingSecret: authSecretName,
      },
      dataPlane: {
        mode: 'in-cluster',
      },
      networkPolicy: {
        enabled: true,
        api: {
          httpIngressFrom: [{
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': 'n8n',
              },
            },
          }],
          metricsIngressFrom: [{
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': 'k8s-monitoring',
              },
            },
          }],
        },
        runner: {
          ingressFrom: [{
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': 'k8s-monitoring',
              },
            },
          }],
        },
      },
      monitoring: {
        serviceMonitor: {
          enabled: true,
        },
      },
      tls: {
        mode: 'certManager',
        certManager: {
          issuerRef: {
            name: 'n8n-sandbox-ca',
            kind: 'Issuer',
            group: 'cert-manager.io',
          },
        },
      },
      api: {
        ingress: {
          enabled: false,
        },
        config: {
          metricsListenAddr: ':9100',
        },
        persistence: {
          enabled: true,
          size: '1Gi',
          storageClass: 'longhorn-v1',
        },
      },
      runner: {
        isolation: 'sysbox',
        sysbox: {
          runtime: {
            runtimeClassName: 'sysbox-runc',
            hostUsers: false,
          },
          scheduling: {
            nodeSelector: {
              'sysbox-install': null,  // Delete the chart default.
              'sysbox-runtime': 'running',
            },
            tolerations: [],
          },
        },
        dockerDataRoot: {
          persistence: {
            enabled: true,
            size: '64Gi',
            storageClass: 'longhorn-v1',
          },
        },
      },
    },
  }),

  // Sandbox code may reach the public internet, but not cluster, host, or
  // private-network addresses. DNS and runner-to-API control traffic are the
  // only internal exceptions.
  runnerEgressPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'sandbox-runner-egress',
      namespace: namespace,
    },
    spec: {
      podSelector: {
        matchLabels: sandboxLabels + { 'app.kubernetes.io/component': 'sysbox-runner' },
      },
      policyTypes: ['Egress'],
      egress: [
        {
          to: [{
            podSelector: {
              matchLabels: sandboxLabels + { 'app.kubernetes.io/component': 'api' },
            },
          }],
          ports: [{ protocol: 'TCP', port: 9090 }],
        },
        {
          to: [{
            namespaceSelector: {
              matchLabels: { 'kubernetes.io/metadata.name': 'kube-system' },
            },
            podSelector: {
              matchLabels: { 'k8s-app': 'kube-dns' },
            },
          }],
          ports: [
            { protocol: 'UDP', port: 53 },
            { protocol: 'TCP', port: 53 },
          ],
        },
        {
          to: [{
            ipBlock: {
              cidr: '0.0.0.0/0',
              except: [
                '10.0.0.0/8',
                '100.64.0.0/10',
                '127.0.0.0/8',
                '169.254.0.0/16',
                '172.16.0.0/12',
                '192.168.0.0/16',
              ],
            },
          }],
        },
      ],
    },
  },

  // SANDBOX_API_KEYS is comma-delimited, so its keys must never contain commas.
  authGenerator:
    password.new(authSecretName)
    + password.metadata.withNamespace(namespace)
    + password.spec.withLength(50)
    + password.spec.withSymbols(0)
    + password.spec.withAllowRepeat(true),

  auth:
    externalSecret.new(authSecretName)
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.target.withName(authSecretName)
    + externalSecret.spec.target.withCreationPolicy('Owner')
    + externalSecret.spec.target.template.withData({
      'api-keys': '{{ .password }}',
      'runner-registration-token': '{{ .password }}',
      'runner-api-key': '{{ .password }}',
      'runner-api-keys': '{{ .password }}',
    })
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'Password',
          name: authSecretName,
        },
      },
    }]),

  ca:
    certificate.new('n8n-sandbox-ca')
    + certificate.metadata.withNamespace(namespace)
    + certificate.spec.withSecretName('n8n-sandbox-ca')
    + certificate.spec.withCommonName('n8n-sandbox-ca')
    + certificate.spec.withIsCA(true)
    + certificate.spec.withUsages(['cert sign', 'crl sign', 'digital signature'])
    + certificate.spec.issuerRef.withName('selfsigned')
    + certificate.spec.issuerRef.withKind('ClusterIssuer'),

  caIssuer:
    issuer.new('n8n-sandbox-ca')
    + issuer.metadata.withNamespace(namespace)
    + issuer.spec.ca.withSecretName('n8n-sandbox-ca'),

  authReaderServiceAccount:
    serviceAccount.new(authReaderName)
    + serviceAccount.metadata.withNamespace(namespace)
    + serviceAccount.withAutomountServiceAccountToken(false),

  authReaderRole:
    role.new(authReaderName)
    + role.metadata.withNamespace(namespace)
    + role.withRules([
      {
        apiGroups: [''],
        resources: ['secrets'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['authorization.k8s.io'],
        resources: ['selfsubjectrulesreviews'],
        verbs: ['create'],
      },
    ]),

  authReaderRoleBinding:
    roleBinding.new(authReaderName)
    + roleBinding.metadata.withNamespace(namespace)
    + roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + roleBinding.roleRef.withKind('Role')
    + roleBinding.roleRef.withName(authReaderName)
    + roleBinding.withSubjects([{
      kind: 'ServiceAccount',
      name: authReaderName,
      namespace: namespace,
    }]),

  authStore:
    clusterSecretStore.new('n8n-sandbox-auth')
    + { spec+: { conditions: [{ namespaces: ['n8n'] }] } }
    + clusterSecretStore.spec.provider.kubernetes.withRemoteNamespace(namespace)
    + clusterSecretStore.spec.provider.kubernetes.server.withUrl('https://kubernetes.default.svc')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withType('ConfigMap')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withName('kube-root-ca.crt')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withKey('ca.crt')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withNamespace(namespace)
    + clusterSecretStore.spec.provider.kubernetes.auth.serviceAccount.withName(authReaderName)
    + clusterSecretStore.spec.provider.kubernetes.auth.serviceAccount.withNamespace(namespace),
}
