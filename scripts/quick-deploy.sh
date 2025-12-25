#!/usr/bin/env bash
set -euo pipefail

# Quick deployment script - prompts for required values
# Usage: ./scripts/quick-deploy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Pulse Quick Deployment"
echo "=========================================="
echo

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker."
    exit 1
fi
echo "✅ Docker found"

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi
echo "✅ kubectl found"

if ! command -v helm &> /dev/null; then
    echo "❌ Helm not found. Please install Helm."
    exit 1
fi
echo "✅ Helm found"

echo

# Prompt for Docker registry
echo "Docker Registry Configuration:"
read -p "Registry URL [docker.io]: " DOCKER_REGISTRY
DOCKER_REGISTRY=${DOCKER_REGISTRY:-docker.io}

read -p "Registry Username: " DOCKER_USERNAME
if [ -z "$DOCKER_USERNAME" ]; then
    echo "❌ Username is required"
    exit 1
fi

read -sp "Registry Password (or press Enter to use existing docker login): " DOCKER_PASSWORD
echo

read -p "Docker Namespace/Org [${DOCKER_USERNAME}]: " DOCKER_NAMESPACE
DOCKER_NAMESPACE=${DOCKER_NAMESPACE:-$DOCKER_USERNAME}

read -p "Docker Image Name [pulse]: " DOCKER_IMAGE
DOCKER_IMAGE=${DOCKER_IMAGE:-pulse}

echo

# Prompt for Kubernetes
echo "Kubernetes Configuration:"
read -p "Kubernetes Namespace [default]: " KUBERNETES_NAMESPACE
KUBERNETES_NAMESPACE=${KUBERNETES_NAMESPACE:-pulse}

read -p "Helm Release Name [pulse]: " HELM_RELEASE_NAME
HELM_RELEASE_NAME=${HELM_RELEASE_NAME:-pulse}

echo

# Confirm
echo "=========================================="
echo "Configuration Summary:"
echo "  Registry: ${DOCKER_REGISTRY}"
echo "  Username: ${DOCKER_USERNAME}"
echo "  Namespace: ${DOCKER_NAMESPACE}"
echo "  Image: ${DOCKER_IMAGE}"
echo "  K8s Namespace: ${KUBERNETES_NAMESPACE}"
echo "  Helm Release: ${HELM_RELEASE_NAME}"
echo "=========================================="
echo

read -p "Proceed with deployment? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo

# Export variables and run deployment
export DOCKER_REGISTRY
export DOCKER_USERNAME
if [ -n "$DOCKER_PASSWORD" ]; then
    export DOCKER_PASSWORD
fi
export DOCKER_NAMESPACE
export DOCKER_IMAGE
export KUBERNETES_NAMESPACE
export HELM_RELEASE_NAME

# Run the main deployment script
"$SCRIPT_DIR/build-and-deploy.sh"

