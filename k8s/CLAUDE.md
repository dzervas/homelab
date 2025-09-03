# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Kubernetes homelab managed entirely through Terraform using the Kubernetes provider. The infrastructure follows a declarative approach where all workloads are defined as Terraform resources rather than raw YAML manifests.

**IMPORTANT**: Always use Terraform to deploy Kubernetes workloads using the kubernetes provider instead of YAML files.

## Key Components

### Terraform Setup
- **Backend**: Kubernetes backend storing state in `kube-system` namespace with suffix `homelab-k8s`
- **Context**: Uses `gr` kubeconfig context
- **Providers**: kubernetes, helm, onepassword

### Secret Management
- **Primary Method**: External Secrets Operator with 1Password integration
- **Configuration**: ClusterSecretStore `1password` connects to vault `k8s-secrets`

**IMPORTANT**: For secrets always use external-secrets with 1password - never hardcode secrets in Terraform files.

### Reusable Module
The `docker-service/` module provides a standardized way to deploy docker applications:
- Supports both Deployment and StatefulSet types
- Built-in ingress, monitoring, and persistent volume support
- Security contexts enabled by default
- Integration with external authentication systems

## Common Commands

### Terraform Operations
```bash
# Plan changes
terraform plan

# Apply changes
terraform apply

# Target specific resource
terraform apply -target=<resource_name>

# Import existing resources
terraform import <resource_type>.<name> <resource_id>
```

### Kubernetes Context
```bash
# Switch to correct context
kubectx gr

# View current context
kubectx -c
```

## Development Patterns

### Adding New Services
1. Create new `.tf` file in root directory
2. Use the `docker-service` module with a docker image if no up to date helm chart exists for the app
3. Configure secrets via external-secrets resources
4. Add appropriate labels for ingress/monitoring integration

### Secret Management Pattern
1. Store secrets in 1Password vault `k8s-secrets`
2. Create ExternalSecret resource referencing the 1password ClusterSecretStore
3. Use standard secret mounting in workload definitions

### Module Usage Example
```hcl
module "myapp" {
  source = "./docker-service"

  name      = "myapp"
  namespace = "myapp"
  image     = "myapp:latest"

  pvs = {
    "/data" = {
      name = "myapp-data"
      size = "10Gi"
    }
  }
}
```

## Variables
- `var.domain`: Default domain (dzerv.art)
- `var.timezone`: Default timezone (Europe/Athens)

## File Organization
- Root `.tf` files: Individual service definitions
- `docker-service/`: Reusable Terraform module for containerized workloads
- `providers.tf`: Provider configurations and 1Password data source
- `vars.tf`: Global variable definitions

Avoid the addition of new global terraform variables

Use generic subdomain names under the default domain as application endpoints
