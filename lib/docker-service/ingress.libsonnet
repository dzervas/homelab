local k = import 'k.libsonnet';

local ingress = k.networking.v1.ingress;
local ingressRule = k.networking.v1.ingressRule;
local httpIngressPath = k.networking.v1.httpIngressPath;

{
  new(name, cfg)::
    local hasIngress = cfg.ingressEnabled && cfg.fqdn != null;
    local middleware = if std.endsWith(cfg.fqdn, '.vpn.dzerv.art') || std.endsWith(cfg.fqdn, '.ts.dzerv.art') then 'traefik-vpnonly@kubernetescrd' else '';

    if hasIngress then {
      ingress:
        ingress.new(name)
        + ingress.metadata.withNamespace(cfg.namespace)
        + ingress.metadata.withAnnotations({
          'cert-manager.io/cluster-issuer': 'letsencrypt',
          'traefik.ingress.kubernetes.io/router.middlewares': middleware,
        } + cfg.ingressAnnotations)
        + ingress.spec.withIngressClassName('traefik')
        + ingress.spec.withRules([
          ingressRule.withHost(cfg.fqdn)
          + ingressRule.http.withPaths([
            httpIngressPath.withPath('/')
            + httpIngressPath.withPathType('ImplementationSpecific')
            + httpIngressPath.backend.service.withName(name)
            + httpIngressPath.backend.service.port.withNumber(cfg.ports[0]),
          ]),
        ])
        + ingress.spec.withTls([{
          hosts: [cfg.fqdn],
          secretName: '%s-cert' % std.strReplace(cfg.fqdn, '.', '-'),
        }]),
    } else {},
}
