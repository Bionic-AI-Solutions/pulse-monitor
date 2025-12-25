#!/usr/bin/env bash
set -euo pipefail

# Install Pulse Agent directly on a Kubernetes Node
# This is the recommended approach - installs the agent binary on the node itself

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
PULSE_URL="${PULSE_URL:-http://192.168.0.220:7655}"
PULSE_TOKEN="${PULSE_TOKEN:-}"
NODE_NAME="${NODE_NAME:-}"
ENABLE_KUBERNETES="${ENABLE_KUBERNETES:-true}"

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

# Get token if not provided
if [ -z "$PULSE_TOKEN" ]; then
    log_info "PULSE_TOKEN not set."
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
    read -p "Enter node name (or press Enter to use first worker node): " NODE_NAME
    if [ -z "$NODE_NAME" ]; then
        # Get first non-control-plane node
        NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.labels.node-role\.kubernetes\.io/control-plane!="")].metadata.name}' 2>/dev/null || \
                   kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -z "$NODE_NAME" ]; then
            NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        fi
        if [ -z "$NODE_NAME" ]; then
            log_error "No nodes found"
            exit 1
        fi
    fi
fi

log_info "Installing Pulse agent on node: $NODE_NAME"
log_info "  Pulse URL: $PULSE_URL"
echo

# Verify node exists
if ! kubectl get node "$NODE_NAME" &> /dev/null; then
    log_error "Node '$NODE_NAME' not found"
    exit 1
fi

# Method 1: Try using kubectl debug (if available)
log_info "Attempting installation via kubectl debug..."

# Create a debug pod
DEBUG_POD="pulse-agent-installer-$(date +%s)"

if kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 --rm --restart=Never -- sh -c "
    apk add --no-cache curl bash
    curl -fsSL $PULSE_URL/install.sh | bash -s -- \
      --url $PULSE_URL \
      --token $PULSE_TOKEN \
      --enable-kubernetes \
      --enable-host
" 2>/dev/null; then
    log_success "Agent installed successfully via kubectl debug"
else
    log_warn "kubectl debug not available or failed, trying alternative method..."
    
    # Method 2: Use a DaemonSet-like approach with hostPath
    log_info "Creating installation pod with host access..."
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $DEBUG_POD
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
    - name: host-usr-local
      mountPath: /host-usr-local
      subPath: usr/local
      readOnly: false
    - name: host-etc
      mountPath: /host-etc
      subPath: etc
      readOnly: false
  volumes:
  - name: host-root
    hostPath:
      path: /
      type: Directory
  - name: host-usr-local
    hostPath:
      path: /usr/local
      type: DirectoryOrCreate
  - name: host-etc
    hostPath:
      path: /etc
      type: Directory
  nodeSelector:
    kubernetes.io/hostname: $NODE_NAME
  restartPolicy: Never
EOF

    log_info "Waiting for installation..."
    sleep 10
    
    # Wait for completion
    if kubectl wait --for=condition=Ready pod/"$DEBUG_POD" --timeout=300s 2>/dev/null; then
        log_info "Installation logs:"
        kubectl logs "$DEBUG_POD" --tail=50 || true
    else
        log_warn "Pod may have completed or failed. Checking logs..."
        kubectl logs "$DEBUG_POD" --tail=100 || true
    fi
    
    # Cleanup
    kubectl delete pod "$DEBUG_POD" --ignore-not-found=true
fi

echo
log_success "=========================================="
log_success "Installation complete!"
log_success "=========================================="
echo
log_info "The agent should now be running on node: $NODE_NAME"
log_info ""
log_info "To verify installation, SSH to the node and run:"
log_info "  systemctl status pulse-agent"
log_info "  journalctl -u pulse-agent -f"
echo
log_info "Or check in Pulse UI: $PULSE_URL → Dashboard"
log_info "Your Kubernetes cluster should appear within a few minutes."

