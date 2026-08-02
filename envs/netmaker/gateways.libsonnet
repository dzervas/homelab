local gatewayApi = import 'gateway-api-libsonnet/1.4-experimental/main.libsonnet';
local lab = import 'labsonnet.libsonnet';

local udpRoute = gatewayApi.gateway.v1alpha2.udpRoute;
local namespace = 'netmaker';

local gateway(name, port, tokenKey) =
  lab.new(name, 'gravitl/netclient:v1.4.0')
  + lab.withNamespace(namespace)
  + lab.withType('StatefulSet')
  + lab.withServiceName(name)
  + lab.withPort({ name: 'wireguard', port: port, protocol: 'UDP' })
  + lab.withPV('/etc/netclient', {
    name: 'config',
    size: '512Mi',
  })
  + lab.withEnv({
    DAEMON: 'on',
    LOG_LEVEL: 'info',
    PORT: std.toString(port),
    HOST_NAME: name,
  })
  + lab.withSecretEnv({ TOKEN: { name: 'netmaker-op', key: tokenKey } })
  + lab.withAffinityAvoidHomelab()
  + lab.withRunAsUser(0)
  + lab.withSecurityContext({
    runAsNonRoot: false,
    runAsUser: 0,
    runAsGroup: 0,
    allowPrivilegeEscalation: false,
    capabilities: {
      drop: ['ALL'],
      add: ['NET_ADMIN', 'SYS_MODULE'],
    },
  })
  + lab.withPodSecurityContext({
    runAsNonRoot: false,
    fsGroup: 0,
    sysctls: [{ name: 'net.ipv4.ip_forward', value: '1' }],
  });

local route(name, sectionName, serviceName, port) =
  udpRoute.new(name)
  + udpRoute.metadata.withNamespace(namespace)
  + udpRoute.spec.withParentRefs([
    udpRoute.spec.parentRefs.withName('traefik-gateway')
    + udpRoute.spec.parentRefs.withNamespace('traefik')
    + udpRoute.spec.parentRefs.withSectionName(sectionName),
  ])
  + udpRoute.spec.withRules([
    udpRoute.spec.rules.withBackendRefs([
      udpRoute.spec.rules.backendRefs.withName(serviceName)
      + udpRoute.spec.rules.backendRefs.withPort(port),
    ]),
  ]);

{
  // adminGateway: gateway('netmaker-gateway-admin', 51821, 'admin-token'),
  // restrictedGateway: gateway('netmaker-gateway-restricted', 51822, 'restricted-token'),

  adminGatewayRoute:
    route('netmaker-gateway-admin', 'netmaker-admin', 'netmaker-gateway-admin', 51821),
  restrictedGatewayRoute:
    route('netmaker-gateway-restricted', 'netmaker-restricted', 'netmaker-gateway-restricted', 51822),
}
