// CloakBrowser that Hermes drives over CDP (and fills logins into from
// its 1Password vault). Its own pod, so it can have internet egress while the
// hermes pod doesn't.
local netpol = import 'helpers/netpol.libsonnet';
local lab = import 'labsonnet.libsonnet';

local namespace = 'hermes';

// Keep the existing CDP address so Hermes' managed configuration stays unchanged
local clusterIP = '10.43.0.52';

{
  cdpUrl:: 'http://%s:9222' % clusterIP,

  browser:
    lab.new('browser', 'cloakhq/cloakbrowser:latest')
    + lab.withNamespace(namespace)
    + lab.withArgs(['cloakserve'])
    + lab.withPort({ port: 9222, name: 'cdp' })
    + lab.withEmptyDir('/dev/shm')
    // cloakserve checks this path's existence to bind 0.0.0.0; containerd has no Docker marker
    + lab.withPV('/run/.containerenv', { name: 'container-marker', emptyDir: true })
    + lab.withEnv({ HOME: '/tmp' })
    + lab.withResources({ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } })
    + {
      workload+: { spec+: { template+: { spec+: {
        runtimeClassName: 'gvisor',
        automountServiceAccountToken: false,
        securityContext+: { seccompProfile: { type: 'RuntimeDefault' } },
        // Chrome crashes with BUS_ADRERR on the default 64Mi /dev/shm
        volumes: [
          if std.objectHas(v, 'emptyDir') then v { emptyDir: { medium: 'Memory', sizeLimit: '1Gi' } } else v
          for v in super.volumes
        ],
      } } } },
      service+: { spec+: { clusterIP: clusterIP } },
    },

  browserEgress: netpol.egress('browser-egress', namespace, { 'app.kubernetes.io/name': 'browser' }, {
    dnsNames: ['*'],
    cidrs: [netpol.internet],
  }),

  browserIngress: netpol.onlyFromNamespaces('browser-ingress', namespace, { 'app.kubernetes.io/name': 'browser' }, [namespace]),
}
