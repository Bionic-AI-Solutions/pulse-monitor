#!/usr/bin/env bash
set -euo pipefail

# Create Kubernetes secret for Docker registry authentication
# Usage: ./scripts/create-registry-secret.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:-}"
SECRET_NAME="${SECRET_NAME:-docker-registry-secret}"
KUBERNETES_NAMESPACE="${KUBERNETES_NAMESPACE:-pulse}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found"
    exit 1
fi

# Get credentials
if [ -z "$DOCKER_USERNAME" ]; then
    read -p "Docker Registry Username: " DOCKER_USERNAME
    if [ -z "$DOCKER_USERNAME" ]; then
        log_error "Username is required"
        exit 1
    fi
fi

if [ -z "$DOCKER_PASSWORD" ]; then
    read -sp "Docker Registry Password: " DOCKER_PASSWORD
    echo
    if [ -z "$DOCKER_PASSWORD" ]; then
        log_warn "Password is empty, proceeding anyway (may use existing docker login)"
    fi
fi

log_info "Creating registry secret..."
log_info "  Registry: $DOCKER_REGISTRY"
log_info "  Username: $DOCKER_USERNAME"
log_info "  Secret Name: $SECRET_NAME"
log_info "  Namespace: $KUBERNETES_NAMESPACE"

# Create namespace if it doesn't exist
if ! kubectl get namespace "$KUBERNETES_NAMESPACE" &> /dev/null; then
    log_info "Creating namespace $KUBERNETES_NAMESPACE..."
    kubectl create namespace "$KUBERNETES_NAMESPACE"
fi

# Delete existing secret if it exists
if kubectl get secret "$SECRET_NAME" -n "$KUBERNETES_NAMESPACE" &> /dev/null; then
    log_info "Deleting existing secret..."
    kubectl delete secret "$SECRET_NAME" -n "$KUBERNETES_NAMESPACE"
fi

# Create the secret
if kubectl create secret docker-registry "$SECRET_NAME" \
    --docker-server="$DOCKER_REGISTRY" \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --namespace="$KUBERNETES_NAMESPACE"; then
    log_success "Registry secret created successfully"
    
    log_info "To use this secret in your Helm deployment, add to values.yaml:"
    echo "imagePullSecrets:"
    echo "  - name: $SECRET_NAME"
    echo
    log_info "Or update the deployment script to include imagePullSecrets"
else
    log_error "Failed to create registry secret"
    exit 1
fi

