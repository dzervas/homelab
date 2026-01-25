local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'ingress';
local customErrorPages = {
  '400': 'Bad Request - The server could not understand the request.',
  '401': 'Unauthorized - Authentication is required to proceed.',
  '402': 'Payment Required - A required payment step is missing.',
  '403': "Forbidden - You don't have permission to access this resource.",
  '404': 'Not Found - The resource could not be located.',
  '405': 'Method Not Allowed - The HTTP method is not supported for this endpoint.',
  '500': 'Internal Server Error - Something unexpected happened on our side.',
  '501': 'Not Implemented - This feature is not available yet.',
  '502': 'Bad Gateway - Upstream service sent an invalid response.',
  '503': 'Service Unavailable - The service is temporarily overloaded or down for maintenance.',
  '504': 'Gateway Timeout - Upstream service took too long to respond.',
};
local errorCodes = std.sort(std.objectFields(customErrorPages));
local errorTemplate = importstr 'error.html';
local renderErrorPage(code, message) =
  local parts = std.splitLimit(message, '-', 2);
  local messageTitle = std.trim(parts[0]);
  std.strReplace(
    std.strReplace(
      std.strReplace(errorTemplate, '%%STATUS_CODE%%', code),
      '%%STATUS_MESSAGE%%',
      message
    ),
    '%%STATUS_TITLE%%',
    code + ' - ' + messageTitle
  );

local defaultBackend = {
  enabled: true,
  image: {
    registry: 'registry.k8s.io',
    image: 'ingress-nginx/custom-error-pages',
    tag: 'v1.2.3',
  },
  extraVolumes: [{
    name: 'custom-error-pages',
    configMap: {
      name: 'custom-error-pages',
      items: [
        { key: code, path: code + '.html' }
        for code in errorCodes
      ],
    },
  }],
  extraVolumeMounts: [{
    name: 'custom-error-pages',
    mountPath: '/www',
  }],
};

{
  namespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({
      'pod-security.kubernetes.io/enforce': 'privileged',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    }),

  ingressNginx: helm.template('ingress-nginx', '../../charts/ingress-nginx', {
    namespace: namespace,
    values: {
      controller: {
        // TODO: Eliminate this
        allowSnippetAnnotations: true,
        enableAnnotationValidations: true,

        watchIngressWithoutClass: true,
        ingressClassResource: { default: true },

        networkPolicy: { enabled: true },

        kind: 'DaemonSet',
        hostPort: { enabled: true },
        service: { type: 'ClusterIP' },

        // Change the default self-signed cert to a Let's Encrypt certificate
        // extraArgs: { 'default-ssl-certificate': 'ingress/letsencrypt-prod' },

        config: {
          'custom-http-errors': std.join(',', errorCodes),
          'annotations-risk-level': 'Critical',
        },

        metrics: {
          enabled: true,
          serviceMonitor: { enabled: true },
        },
      },

      defaultBackend: defaultBackend,
    },
  }),

  ingressNginxVPN: helm.template('ingress-nginx-vpn', '../../charts/ingress-nginx', {
    namespace: namespace,
    values: {
      controller: {
        allowSnippetAnnotations: true,
        enableAnnotationValidations: true,

        ingressClass: 'vpn',
        ingressClassResource: {
          name: 'vpn',
          controllerValue: 'k8s.io/vpn',
        },

        networkPolicy: { enabled: true },

        kind: 'DaemonSet',
        service: { type: 'ClusterIP' },
        hostPort: {
          enabled: true,
          ports: {
            http: 7080,
            https: 7443,
          },
        },

        // config: { 'custom-http-errors': std.join(',', errorCodes) },
      },

      // defaultBackend: defaultBackend,
    },
  }),

  customErrorPagesConfigMap:
    k.core.v1.configMap.new('custom-error-pages')
    + k.core.v1.configMap.metadata.withNamespace(namespace)
    + k.core.v1.configMap.withData(
      std.foldl(
        function(acc, code)
          acc { [code]: renderErrorPage(code, customErrorPages[code]) },
        errorCodes,
        {}
      )
    ),

  vpnNetworkPolicy:
    k.networking.v1.networkPolicy.new('allow-vpn')
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/instance': 'ingress-nginx-vpn' })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([{
      from: [{
        // For some reason VPN CIDR doesn't work
        ipBlock: {
          // cidr: '100.100.50.0/24',
          cidr: '0.0.0.0/0',
        },
      }],
      ports: [
        { port: 80, protocol: 'TCP' },
        { port: 443, protocol: 'TCP' },
        { port: 7080, protocol: 'TCP' },
        { port: 7443, protocol: 'TCP' },
      ],
    }]),
}
