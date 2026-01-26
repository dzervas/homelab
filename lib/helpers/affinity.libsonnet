// Affinity helper functions for high availability configurations
//
// These helpers provide reusable affinity configurations to ensure
// critical workloads are scheduled on reliable nodes.
//
// Thanks @looselyrigorous! <3

{
  // Require specific providers
  requireProviders(providers):: {
    nodeAffinity: {
      requiredDuringSchedulingIgnoredDuringExecution: {
        nodeSelectorTerms: [{
          matchExpressions: [{
            key: 'provider',
            operator: 'In',
            values: providers,
          }],
        }],
      },
    },
  },

  // Avoid specific providers (generalized version)
  avoidProviders(providers):: {
    nodeAffinity: {
      requiredDuringSchedulingIgnoredDuringExecution: {
        nodeSelectorTerms: [{
          matchExpressions: [{
            key: 'provider',
            operator: 'NotIn',
            values: providers,
          }],
        }],
      },
    },
  },

  // Prefer specific providers (soft preference)
  preferProviders(providers, weight=100):: {
    nodeAffinity: {
      preferredDuringSchedulingIgnoredDuringExecution: [{
        weight: weight,
        preference: {
          matchExpressions: [{
            key: 'provider',
            operator: 'In',
            values: providers,
          }],
        },
      }],
    },
  },

  // Pod anti-affinity to spread replicas across nodes
  spreadAcrossNodes(labelSelector):: {
    podAntiAffinity: {
      preferredDuringSchedulingIgnoredDuringExecution: [{
        weight: 100,
        podAffinityTerm: {
          labelSelector: {
            matchLabels: labelSelector,
          },
          topologyKey: 'kubernetes.io/hostname',
        },
      }],
    },
  },

  // Combine multiple affinity configurations
  combine(affinities):: std.foldl(
    function(acc, affinity) std.mergePatch(acc, affinity),
    affinities,
    {}
  ),

  // Affinity to avoid homelab provider nodes (they're flaky)
  // Use this for controller components that need high availability
  avoidHomelab:: self.avoidProviders(['homelab']),

  // Prefer oracle provider nodes (most reliable and low latency)
  preferOracle:: self.preferProviders(['oracle']),

  // Alias for common use case
  ha:: self.avoidHomelab,
  lowLatency:: self.preferOracle,
}
