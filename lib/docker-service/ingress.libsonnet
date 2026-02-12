local k = import 'k.libsonnet';

local ingress = k.networking.v1.ingress;
local ingressRule = k.networking.v1.ingressRule;
local httpIngressPath = k.networking.v1.httpIngressPath;

{
  authAnnotation(auth='mtls')::
    if auth == 'vpn' then
      { 'traefik.ingress.kubernetes.io/router.middlewares': 'traefik-vpnonly@kubernetescrd' }
    else if auth == 'magicentry' then
      { 'traefik.ingress.kubernetes.io/router.middlewares': 'traefik-magicentry@kubernetescrd' }
    else if auth == 'mtls' then
      { 'traefik.ingress.kubernetes.io/router.tls.options': 'traefik-mtls@kubernetescrd' }
    else if auth == 'public' then
      {}
    else
      error 'Unsupported auth type for ingress',

  new(name, cfg)::
    local hasIngress = cfg.ingressEnabled && cfg.fqdn != null;

    if hasIngress then {
      ingress:
        ingress.new(name)
        + ingress.metadata.withNamespace(cfg.namespace)
        + ingress.metadata.withAnnotations(
          { 'cert-manager.io/cluster-issuer': 'letsencrypt' }
          + $.authAnnotation(cfg.auth)
          + cfg.ingressAnnotations
        )
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
