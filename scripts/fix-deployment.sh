#!/usr/bin/env bash
set -euo pipefail

# Quick fix script for the current deployment issue
# This will create the registry secret and redeploy

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_USERNAME="${DOCKER_USERNAME:-docker4zerocool}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:-}"
KUBERNETES_NAMESPACE="${KUBERNETES_NAMESPACE:-pulse}"
HELM_RELEASE_NAME="${HELM_RELEASE_NAME:-pulse}"

echo "=========================================="
echo "Fixing Pulse Deployment"
echo "=========================================="
echo

# Create namespace if it doesn't exist
if ! kubectl get namespace "$KUBERNETES_NAMESPACE" &> /dev/null; then
    echo "Creating namespace: $KUBERNETES_NAMESPACE"
    kubectl create namespace "$KUBERNETES_NAMESPACE"
    echo "✅ Namespace created"
fi

# Get credentials if not set
if [ -z "$DOCKER_PASSWORD" ]; then
    echo "Docker registry credentials needed to create pull secret."
    read -p "Username [${DOCKER_USERNAME}]: " input_user
    DOCKER_USERNAME=${input_user:-$DOCKER_USERNAME}
    
    read -sp "Password: " DOCKER_PASSWORD
    echo
    if [ -z "$DOCKER_PASSWORD" ]; then
        echo "❌ Password is required"
        exit 1
    fi
fi

# Create registry secret
echo "Creating registry secret..."
SECRET_NAME="docker-registry-secret"

# Delete existing secret if it exists
kubectl delete secret "$SECRET_NAME" -n "$KUBERNETES_NAMESPACE" 2>/dev/null || true

# Create new secret
kubectl create secret docker-registry "$SECRET_NAME" \
    --docker-server="$DOCKER_REGISTRY" \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --namespace="$KUBERNETES_NAMESPACE"

echo "✅ Registry secret created"

# Get current image from deployment (try pulse namespace first, then default for migration)
CURRENT_IMAGE=$(kubectl get deployment pulse -n "$KUBERNETES_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || \
                kubectl get deployment pulse -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
if [ -z "$CURRENT_IMAGE" ]; then
    echo "⚠️  Could not get current image, using default"
    CURRENT_IMAGE="docker.io/docker4zerocool/pulse:5.0.3"
fi

echo "Current image: $CURRENT_IMAGE"

# Update deployment with imagePullSecrets
echo "Updating deployment with imagePullSecret..."

# Patch the deployment to add imagePullSecrets
kubectl patch deployment pulse -n "$KUBERNETES_NAMESPACE" -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"docker-registry-secret"}]}}}}'

echo "✅ Deployment updated"

# Wait for rollout
echo "Waiting for rollout..."
kubectl rollout status deployment/pulse -n "$KUBERNETES_NAMESPACE" --timeout=5m

echo
echo "=========================================="
echo "✅ Deployment fixed!"
echo "=========================================="
echo
echo "Check pod status:"
kubectl get pods -n "$KUBERNETES_NAMESPACE" -l app.kubernetes.io/name=pulse

