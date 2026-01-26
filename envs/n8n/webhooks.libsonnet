local k = import 'k.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';

local ing = k.networking.v1.ingress;
local ingressRule = k.networking.v1.ingressRule;
local httpIngressPath = k.networking.v1.httpIngressPath;

local namespace = 'n8n';
local domain = 'dzerv.art';
local webhookHost = 'hook.' + domain;

{
  // Additional ingress for webhook endpoints on hook.dzerv.art
  n8nWebhooks:
    ing.new('n8n-webhooks')
    + ing.metadata.withNamespace(namespace)
    + ing.metadata.withAnnotations(ingress.sslOnlyAnnotations {
      'nginx.ingress.kubernetes.io/proxy-body-size': '16m',
    })
    + ing.spec.withIngressClassName('nginx')
    + ing.spec.withRules([
      ingressRule.withHost(webhookHost)
      + ingressRule.http.withPaths([
        httpIngressPath.withPath('/webhook/')
        + httpIngressPath.withPathType('Prefix')
        + httpIngressPath.backend.service.withName('n8n')
        + httpIngressPath.backend.service.port.withNumber(5678),
        httpIngressPath.withPath('/webhook-test/')
        + httpIngressPath.withPathType('Prefix')
        + httpIngressPath.backend.service.withName('n8n')
        + httpIngressPath.backend.service.port.withNumber(5678),
        httpIngressPath.withPath('/webhook-waiting/')
        + httpIngressPath.withPathType('Prefix')
        + httpIngressPath.backend.service.withName('n8n')
        + httpIngressPath.backend.service.port.withNumber(5678),
      ]),
    ])
    + ing.spec.withTls([{
      hosts: [webhookHost],
      secretName: std.strReplace(webhookHost, '.', '-') + '-webhook-cert',
    }]),
}
