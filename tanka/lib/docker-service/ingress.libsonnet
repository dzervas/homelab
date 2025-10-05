local k = import "k.libsonnet";

local ingress = k.networking.v1.ingress;
local ingressRule = k.networking.v1.ingressRule;
local httpIngressPath = k.networking.v1.httpIngressPath;

{
  new(name, cfg)::
    local hasIngress = cfg.ingressEnabled && cfg.fqdn != null;

    if hasIngress then {
      ingress: ingress.new(name)
               + ingress.metadata.withNamespace(cfg.namespace)
               + ingress.metadata.withAnnotations({
                 "cert-manager.io/cluster-issuer": "letsencrypt",
                 "nginx.ingress.kubernetes.io/ssl-redirect": "true",
               } + cfg.ingressAnnotations)
               + ingress.spec.withIngressClassName("nginx")
               + ingress.spec.withRules([
                 ingressRule.withHost(cfg.fqdn)
                 + ingressRule.http.withPaths([
                   httpIngressPath.withPath("/")
                   + httpIngressPath.withPathType("Prefix")
                   + httpIngressPath.backend.service.withName(name)
                   + httpIngressPath.backend.service.port.withNumber(cfg.port),
                 ]),
               ])
               + ingress.spec.withTls([ {
                 hosts: [ cfg.fqdn ],
                 secretName: "%s-cert" % std.strReplace(cfg.fqdn, ".", "-"),
               } ]),
    } else {},
}
