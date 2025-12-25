#!/usr/bin/env bash
set -euo pipefail

# Migrate Pulse deployment from default namespace to pulse namespace
# This script will:
# 1. Create the pulse namespace
# 2. Export resources from default namespace
# 3. Import them into pulse namespace
# 4. Delete the old deployment from default namespace

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-pulse}"
HELM_RELEASE_NAME="${HELM_RELEASE_NAME:-pulse}"

echo "=========================================="
echo "Migrating Pulse to $TARGET_NAMESPACE namespace"
echo "=========================================="
echo

# Check if source deployment exists
if ! kubectl get deployment "$HELM_RELEASE_NAME" -n "$SOURCE_NAMESPACE" &> /dev/null; then
    echo "⚠️  No deployment found in $SOURCE_NAMESPACE namespace"
    echo "   Proceeding with fresh deployment in $TARGET_NAMESPACE namespace"
    SOURCE_EXISTS=false
else
    SOURCE_EXISTS=true
    echo "✅ Found deployment in $SOURCE_NAMESPACE namespace"
fi

# Create target namespace
if ! kubectl get namespace "$TARGET_NAMESPACE" &> /dev/null; then
    echo "Creating namespace: $TARGET_NAMESPACE"
    kubectl create namespace "$TARGET_NAMESPACE"
    echo "✅ Namespace created"
else
    echo "✅ Namespace $TARGET_NAMESPACE already exists"
fi

# Check if target deployment already exists
if kubectl get deployment "$HELM_RELEASE_NAME" -n "$TARGET_NAMESPACE" &> /dev/null; then
    echo "⚠️  Deployment already exists in $TARGET_NAMESPACE namespace"
    read -p "Do you want to delete it and migrate? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Migration cancelled"
        exit 0
    fi
    echo "Deleting existing deployment..."
    helm uninstall "$HELM_RELEASE_NAME" -n "$TARGET_NAMESPACE" 2>/dev/null || \
    kubectl delete deployment "$HELM_RELEASE_NAME" -n "$TARGET_NAMESPACE" 2>/dev/null || true
fi

if [ "$SOURCE_EXISTS" = "true" ]; then
    echo
    echo "Migrating resources from $SOURCE_NAMESPACE to $TARGET_NAMESPACE..."
    
    # Get the image from source deployment
    SOURCE_IMAGE=$(kubectl get deployment "$HELM_RELEASE_NAME" -n "$SOURCE_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
    
    # Get registry secret if it exists
    if kubectl get secret docker-registry-secret -n "$SOURCE_NAMESPACE" &> /dev/null; then
        echo "Copying registry secret..."
        kubectl get secret docker-registry-secret -n "$SOURCE_NAMESPACE" -o yaml | \
            sed "s/namespace: $SOURCE_NAMESPACE/namespace: $TARGET_NAMESPACE/" | \
            kubectl apply -f -
        echo "✅ Registry secret copied"
    fi
    
    # Get PVC if it exists
    if kubectl get pvc -n "$SOURCE_NAMESPACE" -l app.kubernetes.io/name=pulse 2>/dev/null | grep -q pulse; then
        echo "⚠️  Found PVC in $SOURCE_NAMESPACE namespace"
        echo "   PVCs cannot be moved between namespaces directly."
        echo "   You may need to manually copy data or recreate the PVC."
        read -p "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Migration cancelled"
            exit 0
        fi
    fi
    
    echo
    echo "Deleting deployment from $SOURCE_NAMESPACE namespace..."
    helm uninstall "$HELM_RELEASE_NAME" -n "$SOURCE_NAMESPACE" 2>/dev/null || \
    kubectl delete deployment "$HELM_RELEASE_NAME" -n "$SOURCE_NAMESPACE" 2>/dev/null || true
    
    echo "✅ Old deployment removed"
fi

echo
echo "=========================================="
echo "✅ Migration preparation complete!"
echo "=========================================="
echo
echo "Next steps:"
echo "1. Deploy Pulse to the $TARGET_NAMESPACE namespace:"
echo "   ./scripts/build-and-deploy.sh"
echo
echo "   Or if you just need to fix the current deployment:"
echo "   ./scripts/fix-deployment.sh"
echo
echo "2. Verify deployment:"
echo "   kubectl get pods -n $TARGET_NAMESPACE"
echo
echo "3. (Optional) Clean up default namespace:"
echo "   kubectl delete secret docker-registry-secret -n $SOURCE_NAMESPACE 2>/dev/null || true"

