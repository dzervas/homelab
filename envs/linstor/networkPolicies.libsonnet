local k = import 'k.libsonnet';
local networkPolicy = k.networking.v1.networkPolicy;

{
  // The csi-node pods run in host network and they need to be able to reach the controller pod
  // Host networking pods means that they have an IP from a non-k8s CIDR, hence the 0/0 CIDR
  linstorHostNetworkPolicy:
    networkPolicy.new('allow-hostnetwork-controller-access')
    + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/component': 'linstor-controller' })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([{
      from: [{ ipBlock: { cidr: '0.0.0.0/0' } }],
      ports: [{ port: 3370, endPort: 3371, protocol: 'TCP' }],
    }]),

  // This is absolutely needed
  operatorWebhookNetworkPolicy:
    k.networking.v1.networkPolicy.new('piraeus-webhook')
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/name': 'piraeus-datastore',
      'app.kubernetes.io/component': 'piraeus-operator',
      'app.kubernetes.io/instance': 'piraeus',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([
      {
        from: [
          { ipBlock: { cidr: '0.0.0.0/0' } },
        ],
        ports: [{ protocol: 'TCP', port: 9443 }],  // The pod listens on 9443 but the service exposes 443!
      },
    ]),

  // Unsure if this is required - is only the controller speaking to the satellites?
  satelliteNetworkPolicy:
    k.networking.v1.networkPolicy.new('linstor-satellite')
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/component': 'linstor-satellite',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([
      {
        from: [
          { namespaceSelector: {} },
          { podSelector: {} },
          { ipBlock: { cidr: '0.0.0.0/0' } },
        ],
        ports: [
          { protocol: 'TCP', port: 3367 },  // satellite
          { protocol: 'TCP', port: 9942 },  // drbd-reactor
        ],
      },
    ]),
}
