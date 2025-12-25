#!/usr/bin/env bash
set -euo pipefail

# Pulse Build, Push, and Deploy Script
# This script builds the Docker image, pushes it to a registry, and deploys to Kubernetes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_IMAGE="${DOCKER_IMAGE:-pulse}"
DOCKER_NAMESPACE="${DOCKER_NAMESPACE:-${DOCKER_USERNAME:-rcourtman}}"
KUBERNETES_NAMESPACE="${KUBERNETES_NAMESPACE:-pulse}"
HELM_RELEASE_NAME="${HELM_RELEASE_NAME:-pulse}"
HELM_CHART_PATH="${HELM_CHART_PATH:-$PROJECT_ROOT/deploy/helm/pulse}"
SKIP_BUILD="${SKIP_BUILD:-false}"
SKIP_PUSH="${SKIP_PUSH:-false}"
SKIP_DEPLOY="${SKIP_DEPLOY:-false}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"
PUSH_MULTI_ARCH="${PUSH_MULTI_ARCH:-false}"
IMAGE_PULL_SECRET="${IMAGE_PULL_SECRET:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-15m}"
CREATE_REGISTRY_SECRET="${CREATE_REGISTRY_SECRET:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Read version from VERSION file
get_version() {
    if [ -f "$PROJECT_ROOT/VERSION" ]; then
        cat "$PROJECT_ROOT/VERSION" | tr -d '\n'
    else
        log_error "VERSION file not found at $PROJECT_ROOT/VERSION"
        exit 1
    fi
}

# Get git commit hash
get_git_commit() {
    if command -v git &> /dev/null && [ -d "$PROJECT_ROOT/.git" ]; then
        git rev-parse --short HEAD 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Build Docker image
build_image() {
    local version="$1"
    local git_commit="$2"
    local image_tag="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:${version}"
    local image_tag_latest="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:latest"
    local image_tag_commit="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:${version}-${git_commit}"

    log_info "Building Docker image..."
    log_info "  Version: $version"
    log_info "  Git Commit: $git_commit"
    log_info "  Registry: $DOCKER_REGISTRY"
    log_info "  Image: $DOCKER_NAMESPACE/$DOCKER_IMAGE"
    log_info "  Platform: $BUILD_PLATFORM"

    cd "$PROJECT_ROOT"

    # Enable BuildKit
    export DOCKER_BUILDKIT=1

    # Build arguments
    local build_args=(
        "--platform" "$BUILD_PLATFORM"
        "--target" "runtime"
        "--tag" "$image_tag"
        "--tag" "$image_tag_commit"
        "--file" "Dockerfile"
    )

    # Add latest tag if not a pre-release
    if [[ ! "$version" =~ -.*$ ]]; then
        build_args+=("--tag" "$image_tag_latest")
    fi

    # Add build args if needed
    if [ -n "${PULSE_LICENSE_PUBLIC_KEY:-}" ]; then
        build_args+=("--build-arg" "PULSE_LICENSE_PUBLIC_KEY=${PULSE_LICENSE_PUBLIC_KEY}")
    fi

    # Build the image
    if docker build "${build_args[@]}" .; then
        log_success "Docker image built successfully"
        echo "$image_tag"
        return 0
    else
        log_error "Docker build failed"
        return 1
    fi
}

# Push Docker image
push_image() {
    local version="$1"
    local git_commit="$2"
    local image_tag="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:${version}"
    local image_tag_latest="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:latest"
    local image_tag_commit="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:${version}-${git_commit}"

    log_info "Pushing Docker image to registry..."

    # Check if we need to login
    if [ -n "$DOCKER_USERNAME" ]; then
        log_info "Logging in to Docker registry..."
        if [ -z "${DOCKER_PASSWORD:-}" ]; then
            log_warn "DOCKER_PASSWORD not set, attempting login without password..."
            if ! docker login -u "$DOCKER_USERNAME" "$DOCKER_REGISTRY" 2>/dev/null; then
                log_error "Docker login failed. Please set DOCKER_PASSWORD or run 'docker login' manually"
                return 1
            fi
        else
            echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin "$DOCKER_REGISTRY" || {
                log_error "Docker login failed"
                return 1
            }
        fi
    else
        log_warn "DOCKER_USERNAME not set, skipping login (may fail if registry requires auth)"
    fi

    # Push tags
    local tags_to_push=("$image_tag" "$image_tag_commit")
    if [[ ! "$version" =~ -.*$ ]]; then
        tags_to_push+=("$image_tag_latest")
    fi

    for tag in "${tags_to_push[@]}"; do
        log_info "Pushing $tag..."
        if docker push "$tag"; then
            log_success "Pushed $tag"
        else
            log_error "Failed to push $tag"
            return 1
        fi
    done

    log_success "All images pushed successfully"
    return 0
}

# Deploy to Kubernetes using Helm
deploy_to_kubernetes() {
    local version="$1"
    local image_tag="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:${version}"

    log_info "Deploying to Kubernetes..."
    log_info "  Release: $HELM_RELEASE_NAME"
    log_info "  Namespace: $KUBERNETES_NAMESPACE"
    log_info "  Image: $image_tag"
    log_info "  Chart: $HELM_CHART_PATH"

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        return 1
    fi

    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install Helm."
        return 1
    fi

    # Check if namespace exists, create if not
    if ! kubectl get namespace "$KUBERNETES_NAMESPACE" &> /dev/null; then
        log_info "Creating namespace $KUBERNETES_NAMESPACE..."
        kubectl create namespace "$KUBERNETES_NAMESPACE"
    fi

    # Create registry secret if requested
    if [ "$CREATE_REGISTRY_SECRET" = "true" ] && [ -n "$DOCKER_USERNAME" ]; then
        local secret_name="${IMAGE_PULL_SECRET:-docker-registry-secret}"
        log_info "Creating registry secret: $secret_name"
        
        # Delete existing secret if it exists
        if kubectl get secret "$secret_name" -n "$KUBERNETES_NAMESPACE" &> /dev/null; then
            kubectl delete secret "$secret_name" -n "$KUBERNETES_NAMESPACE" &> /dev/null || true
        fi
        
        # Create the secret
        if [ -n "${DOCKER_PASSWORD:-}" ]; then
            if kubectl create secret docker-registry "$secret_name" \
                --docker-server="$DOCKER_REGISTRY" \
                --docker-username="$DOCKER_USERNAME" \
                --docker-password="$DOCKER_PASSWORD" \
                --namespace="$KUBERNETES_NAMESPACE" &> /dev/null; then
                log_success "Registry secret created"
                IMAGE_PULL_SECRET="$secret_name"
            else
                log_warn "Failed to create registry secret, continuing without it"
            fi
        else
            log_warn "DOCKER_PASSWORD not set, skipping registry secret creation"
        fi
    fi

    # Prepare Helm values
    local helm_values_file=$(mktemp)
    cat > "$helm_values_file" <<EOF
image:
  repository: ${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}
  tag: "${version}"
  pullPolicy: Always
EOF

    # Add imagePullSecrets if secret is provided
    if [ -n "$IMAGE_PULL_SECRET" ]; then
        cat >> "$helm_values_file" <<EOF
imagePullSecrets:
  - name: ${IMAGE_PULL_SECRET}
EOF
        log_info "Using imagePullSecret: $IMAGE_PULL_SECRET"
    fi

    # Add service type if specified
    if [ -n "${SERVICE_TYPE:-}" ]; then
        cat >> "$helm_values_file" <<EOF
service:
  type: ${SERVICE_TYPE}
EOF
        log_info "Service type: $SERVICE_TYPE"
    fi

    log_info "Using Helm values:"
    cat "$helm_values_file"

    # Deploy with Helm
    log_info "Running Helm upgrade..."
    log_info "Timeout: $HELM_TIMEOUT"
    if helm upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART_PATH" \
        --namespace "$KUBERNETES_NAMESPACE" \
        --values "$helm_values_file" \
        --wait \
        --timeout "$HELM_TIMEOUT"; then
        log_success "Helm deployment completed successfully"
        rm -f "$helm_values_file"
        return 0
    else
        log_error "Helm deployment failed"
        rm -f "$helm_values_file"
        return 1
    fi
}

# Main function
main() {
    log_info "=========================================="
    log_info "Pulse Build, Push, and Deploy Script"
    log_info "=========================================="
    echo

    # Get version and git commit
    local version=$(get_version)
    local git_commit=$(get_git_commit)

    log_info "Version: $version"
    log_info "Git Commit: $git_commit"
    echo

    # Build
    local image_tag=""
    if [ "$SKIP_BUILD" != "true" ]; then
        if image_tag=$(build_image "$version" "$git_commit"); then
            log_success "Build completed"
        else
            log_error "Build failed"
            exit 1
        fi
        echo
    else
        log_warn "Skipping build (SKIP_BUILD=true)"
        image_tag="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}:${version}"
    fi

    # Push
    if [ "$SKIP_PUSH" != "true" ]; then
        if push_image "$version" "$git_commit"; then
            log_success "Push completed"
        else
            log_error "Push failed"
            exit 1
        fi
        echo
    else
        log_warn "Skipping push (SKIP_PUSH=true)"
    fi

    # Deploy
    if [ "$SKIP_DEPLOY" != "true" ]; then
        if deploy_to_kubernetes "$version"; then
            log_success "Deployment completed"
            echo
            log_info "Deployment status:"
            kubectl get pods -n "$KUBERNETES_NAMESPACE" -l app.kubernetes.io/name=pulse
        else
            log_error "Deployment failed"
            exit 1
        fi
    else
        log_warn "Skipping deployment (SKIP_DEPLOY=true)"
    fi

    log_success "=========================================="
    log_success "All steps completed successfully!"
    log_success "=========================================="
}

# Show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build, push, and deploy Pulse to Kubernetes.

Environment Variables:
  DOCKER_REGISTRY          Docker registry (default: docker.io)
  DOCKER_USERNAME          Docker registry username
  DOCKER_PASSWORD          Docker registry password (or use 'docker login')
  DOCKER_IMAGE             Docker image name (default: pulse)
  DOCKER_NAMESPACE         Docker namespace/org (default: DOCKER_USERNAME or rcourtman)
  KUBERNETES_NAMESPACE     Kubernetes namespace (default: pulse)
  HELM_RELEASE_NAME        Helm release name (default: pulse)
  HELM_CHART_PATH          Path to Helm chart (default: ./deploy/helm/pulse)
  BUILD_PLATFORM           Build platform (default: linux/amd64)
  SKIP_BUILD               Skip build step (default: false)
  SKIP_PUSH                Skip push step (default: false)
  SKIP_DEPLOY              Skip deploy step (default: false)
  IMAGE_PULL_SECRET         Kubernetes secret name for registry auth
  CREATE_REGISTRY_SECRET    Auto-create registry secret (default: false)
  SERVICE_TYPE              Service type (ClusterIP, LoadBalancer, NodePort) (default: from chart)
  HELM_TIMEOUT              Helm deployment timeout (default: 15m)
  PULSE_LICENSE_PUBLIC_KEY Optional license public key for build

Examples:
  # Full build, push, and deploy
  DOCKER_USERNAME=myuser DOCKER_PASSWORD=mypass ./scripts/build-and-deploy.sh

  # Build only
  SKIP_PUSH=true SKIP_DEPLOY=true ./scripts/build-and-deploy.sh

  # Push and deploy only (skip build)
  SKIP_BUILD=true DOCKER_USERNAME=myuser ./scripts/build-and-deploy.sh

  # Deploy to specific namespace
  KUBERNETES_NAMESPACE=pulse-prod ./scripts/build-and-deploy.sh

EOF
}

# Parse arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# Run main function
main

