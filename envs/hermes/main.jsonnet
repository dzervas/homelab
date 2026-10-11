local k = import 'k.libsonnet';

local mcp = import './mcp.libsonnet';

// Plan and reasoning: docs/research/hermes.md
{
  namespace:
    k.core.v1.namespace.new('hermes')
    + k.core.v1.namespace.metadata.withLabels({
      'pod-security.kubernetes.io/enforce': 'restricted',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    }),

  hermes: import './hermes.libsonnet',
  browser: import './browser.libsonnet',
  workspace: import './workspace.libsonnet',
  mcp: mcp.resources,

  // runsc is registered on every node by nixos/rke2/containerd.nix
  gvisor: {
    apiVersion: 'node.k8s.io/v1',
    kind: 'RuntimeClass',
    metadata: { name: 'gvisor', annotations: { 'tanka.dev/namespaced': 'false' } },
    handler: 'runsc',
    overhead: { podFixed: { cpu: '50m', memory: '64Mi' } },
    scheduling: { nodeSelector: { 'gvisor-runtime': 'running' } },
  },
}
