local k = import 'k.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;

local namespace = 'n8n';

// Use TF-compatible labels for selector
local tfLabels = {
  managed_by: 'terraform',
  service: 'n8n-runners',
};

{
  // n8n-runners deployment (external task runners)
  n8nRunners:
    deployment.new('n8n-runners', 0, [
      container.new('n8n-runners', 'ghcr.io/dzervas/n8n:latest')
      + container.withCommand(['/usr/local/bin/task-runner-launcher'])
      + container.withArgs(['javascript'])
      + container.withImagePullPolicy('Always')
      + container.withEnv([
        {
          name: 'N8N_RUNNERS_AUTH_TOKEN',
          valueFrom: {
            secretKeyRef: {
              name: 'n8n-runner-token',
              key: 'password',
              optional: false,
            },
          },
        },
        { name: 'GENERIC_TIMEZONE', value: timezone },
        { name: 'N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT', value: '60' },
        { name: 'N8N_RUNNERS_MAX_CONCURRENCY', value: '5' },
        { name: 'N8N_RUNNERS_TASK_BROKER_URI', value: 'http://n8n:5679' },
        { name: 'TZ', value: timezone },
      ])
      + container.securityContext.withRunAsNonRoot(true)
      + container.securityContext.withRunAsUser(1000)
      + container.securityContext.withRunAsGroup(1000)
      + container.securityContext.withAllowPrivilegeEscalation(false)
      + container.securityContext.capabilities.withDrop(['ALL']),
    ])
    + deployment.metadata.withNamespace(namespace)
    + deployment.spec.template.metadata.withLabels(tfLabels)
    + deployment.spec.selector.withMatchLabels(tfLabels)
    + deployment.spec.template.spec.withImagePullSecrets([{ name: 'ghcr-cluster-secret' }])
    + deployment.spec.template.spec.securityContext.withFsGroup(1000)
    + deployment.spec.template.spec.securityContext.withRunAsNonRoot(true),

  n8nRunnersService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'n8n-runners',
      namespace: namespace,
      labels: tfLabels,
    },
    spec: {
      selector: tfLabels,
      ports: [{
        port: 80,
        targetPort: 80,
        protocol: 'TCP',
      }],
    },
  },
}
