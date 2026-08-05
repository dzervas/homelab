local affinity = import 'helpers/affinity.libsonnet';
local lab = import 'labsonnet.libsonnet';

local namespace = 'netmaker';
local port = 51821;

// Netmaker Pro enforces per-group access with user groups and resource policies,
// so a single network replaces the OSS two-network split. Remote Access Clients
// (Netmaker Desktop) still need one Remote Access Gateway with a reachable UDP
// endpoint: the operator only builds per-Service ingress proxy pods and never
// promotes a host to a gateway. This netclient host is that gateway; promote it
// once in the dashboard (see README).
{
  gateway:
    lab.new('netmaker-gateway', 'gravitl/netclient:v1.4.0')
    + lab.withNamespace(namespace)
    + lab.withType('StatefulSet')
    + lab.withServiceName('netmaker-gateway')
    + lab.withPort({
      name: 'wireguard',
      port: port,
      udpRoute: {
        gateway: {
          name: 'traefik-gateway',
          namespace: 'traefik',
          sectionName: 'netmaker',
        },
      },
    })
    + lab.withPV('/etc/netclient', {
      name: 'config',
      size: '512Mi',
    })
    + lab.withEnv({
      DAEMON: 'on',
      LOG_LEVEL: 'info',
      PORT: std.toString(port),
      HOST_NAME: 'netmaker-gateway',
    })
    + lab.withSecretEnv({ TOKEN: { name: 'netmaker-op', key: 'enrollment-token' } })
    + lab.withAffinity(affinity.avoidHomelab)
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
    }),
}
