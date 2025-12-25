# Namespace Migration Guide

## Overview

Pulse is now configured to deploy to its own dedicated namespace (`pulse`) instead of the `default` namespace. This provides better isolation and follows Kubernetes best practices.

## Current Status

If you have an existing deployment in the `default` namespace, you have two options:

### Option 1: Migrate Existing Deployment (Recommended)

Use the migration script to move your existing deployment:

```bash
./scripts/migrate-to-pulse-namespace.sh
```

This script will:
- Create the `pulse` namespace
- Copy registry secrets if they exist
- Remove the old deployment from `default` namespace
- Prepare for fresh deployment in `pulse` namespace

**Note**: PVCs (Persistent Volume Claims) cannot be moved between namespaces. If you have data in a PVC, you'll need to either:
- Recreate the PVC in the new namespace (data will be lost)
- Manually copy data between PVCs (advanced)

### Option 2: Fresh Deployment

If you don't need to preserve the existing deployment, simply deploy fresh:

```bash
# Set your credentials
export DOCKER_USERNAME="your-username"
export DOCKER_PASSWORD="your-password"
export CREATE_REGISTRY_SECRET="true"

# Deploy to pulse namespace (default)
./scripts/build-and-deploy.sh
```

## What Changed

### Scripts Updated

All deployment scripts now default to `pulse` namespace:
- `scripts/build-and-deploy.sh` - Default namespace: `pulse`
- `scripts/fix-deployment.sh` - Default namespace: `pulse`
- `scripts/create-registry-secret.sh` - Default namespace: `pulse`
- `scripts/quick-deploy.sh` - Default namespace: `pulse`

### Override Namespace

You can still override the namespace if needed:

```bash
export KUBERNETES_NAMESPACE="custom-namespace"
./scripts/build-and-deploy.sh
```

## Verification

After deployment, verify everything is in the pulse namespace:

```bash
# Check namespace exists
kubectl get namespace pulse

# Check pods
kubectl get pods -n pulse

# Check services
kubectl get svc -n pulse

# Check Helm release
helm list -n pulse
```

## Cleanup (Optional)

If you've successfully migrated and want to clean up the old deployment:

```bash
# Remove old deployment from default namespace
helm uninstall pulse -n default 2>/dev/null || \
kubectl delete deployment pulse -n default 2>/dev/null || true

# Remove old registry secret (if not needed)
kubectl delete secret docker-registry-secret -n default 2>/dev/null || true
```

## Benefits of Dedicated Namespace

1. **Isolation**: Pulse resources are isolated from other applications
2. **Organization**: Easier to manage and find Pulse resources
3. **RBAC**: Can apply namespace-specific permissions
4. **Resource Quotas**: Can set namespace-level resource limits
5. **Best Practice**: Follows Kubernetes recommended practices

## Troubleshooting

If you encounter issues:

1. **Namespace doesn't exist**: The scripts will create it automatically
2. **Permission errors**: Ensure you have permissions to create namespaces
3. **Old deployment conflicts**: Use the migration script or manually delete old resources

For more help, see `DEPLOYMENT_TROUBLESHOOTING.md`.

