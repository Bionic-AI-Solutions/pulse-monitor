#!/usr/bin/env bash
set -euo pipefail

# Install Pulse Agent on a Kubernetes Node
# This installs the agent directly on the node (not as a container)
# The agent will auto-detect Kubernetes and monitor the cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
PULSE_URL="${PULSE_URL:-http://192.168.0.220:7655}"
PULSE_TOKEN="${PULSE_TOKEN:-}"
NODE_NAME="${NODE_NAME:-}"
ENABLE_KUBERNETES="${ENABLE_KUBERNETES:-true}"
ENABLE_HOST="${ENABLE_HOST:-true}"

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
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

# Get token if not provided
if [ -z "$PULSE_TOKEN" ]; then
    log_info "PULSE_TOKEN not set. Please provide your API token."
    log_info "Get your token from: $PULSE_URL → Settings → Security → API Tokens"
    read -sp "Enter API token: " PULSE_TOKEN
    echo
    if [ -z "$PULSE_TOKEN" ]; then
        log_error "Token is required"
        exit 1
    fi
fi

# Get node name if not provided
if [ -z "$NODE_NAME" ]; then
    log_info "Available nodes:"
    kubectl get nodes
    echo
    read -p "Enter node name to install agent on (or press Enter to use first node): " NODE_NAME
    if [ -z "$NODE_NAME" ]; then
        NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -z "$NODE_NAME" ]; then
            log_error "No nodes found"
            exit 1
        fi
    fi
fi

log_info "Installing Pulse agent on node: $NODE_NAME"
log_info "  Pulse URL: $PULSE_URL"
log_info "  Enable Kubernetes: $ENABLE_KUBERNETES"
log_info "  Enable Host: $ENABLE_HOST"
echo

# Verify node exists
if ! kubectl get node "$NODE_NAME" &> /dev/null; then
    log_error "Node '$NODE_NAME' not found"
    exit 1
fi

# Create a Job that will SSH into the node and install the agent
# For K3s, we can use kubectl exec on a pod on that node, or use a DaemonSet with hostPath

log_info "Creating installation job..."

# Get node IP
NODE_IP=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")

if [ -z "$NODE_IP" ]; then
    log_warn "Could not determine node IP, proceeding anyway"
fi

# Create a pod that will install the agent
# We'll use a privileged pod that can access the host filesystem
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pulse-agent-installer
  namespace: default
spec:
  hostNetwork: true
  hostPID: true
  containers:
  - name: installer
    image: alpine:3.20
    command:
    - /bin/sh
    - -c
    - |
      apk add --no-cache curl bash
      curl -fsSL $PULSE_URL/install.sh | bash -s -- \
        --url $PULSE_URL \
        --token $PULSE_TOKEN \
        --enable-kubernetes \
        --enable-host
    securityContext:
      privileged: true
    volumeMounts:
    - name: host-root
      mountPath: /host
      readOnly: false
  volumes:
  - name: host-root
    hostPath:
      path: /
      type: Directory
  nodeSelector:
    kubernetes.io/hostname: $NODE_NAME
  restartPolicy: Never
EOF

log_info "Waiting for installation to complete..."
sleep 5

# Wait for pod to complete
kubectl wait --for=condition=Ready pod/pulse-agent-installer --timeout=300s 2>/dev/null || true

# Check logs
log_info "Installation logs:"
kubectl logs pulse-agent-installer --tail=50 || true

# Cleanup
log_info "Cleaning up installer pod..."
kubectl delete pod pulse-agent-installer --ignore-not-found=true

echo
log_success "=========================================="
log_success "Installation initiated!"
log_success "=========================================="
echo
log_info "The agent should now be running on node: $NODE_NAME"
log_info "Check agent status:"
log_info "  ssh $NODE_NAME 'systemctl status pulse-agent'"
echo
log_info "Or check in Pulse UI: $PULSE_URL → Dashboard"
log_info "Your Kubernetes cluster should appear within a few minutes."

