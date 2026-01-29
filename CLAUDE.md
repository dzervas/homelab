# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a homelab infrastructure repository managing a multi-node Kubernetes cluster with:

- **Tanka/Jsonnet** for Kubernetes manifests (`/envs/`, `/lib/`)
- **NixOS** for node configuration (`/nixos/`)
- **Terraform** for cloud infrastructure (`/infra/`)
- **Helm charts** wrapped in Tanka (`/charts/`)

## Common Commands

### Tanka (Kubernetes)

```bash
tk env list                    # List all environments
tk diff envs/<name>            # Diff single environment
tk apply envs/<name>           # Apply single environment
tk-diff-all                    # Diff all environments
tk-update-check                # Check for chart updates
```

### NixOS Deployment

```bash
# Update existing nodes (uses deploy-rs)
deploy ./nixos#<hostname>

# Deploy to all nodes
deploy ./nixos
```

### Linstor Storage

```bash
kubectl linstor error-reports list # List error reports
kubectl linstor resource list      # List resources
kubectl linstor node list          # List nodes/satellites
```

## SSH and Remote Commands

**Always use full FQDN** for SSH: `ssh gr1.dzerv.art` (not just `gr1`)

**Batch commands** in single SSH calls to reduce round-trips:

```bash
ssh gr1.dzerv.art "cmd1; echo '---'; cmd2; echo '---'; cmd3"
```

## Architecture

### Environments (`/envs/`)

Each environment has:

- `main.jsonnet` - Main configuration
- `spec.json` - Tanka metadata (namespace, context)

### Networking

- `.ts.dzerv.art` / `.vpn.dzerv.art` - VPN ingress class (`vpn`)
- `.dzerv.art` - Public ingress class (`nginx`)

### Storage

**Linstor** - Distributed block storage via Piraeus operator

### Secrets

- 1Password via External Secrets Operator
- ClusterSecretStore: `1password`, vault: `k8s-secrets`

## Key Nodes

- `gr0`, `gr1` - Greek nodes
- `srv0` - Server node
- `fra0`, `fra1` - Frankfurt nodes

All accessible via `<node>.dzerv.art` FQDN.

## Development Environment

Uses `devenv` with direnv.

## Claude Code Rules

- **Never run `tk apply`** - only diff, the user will apply manually
- **Never run `deploy`** - only generate/edit configs, the user will deploy manually
