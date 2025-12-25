#!/usr/bin/env bash
set -euo pipefail

# Install Pulse Agent as Kubernetes DaemonSet
# This script installs the Pulse agent to monitor your Kubernetes cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
PULSE_URL="${PULSE_URL:-http://192.168.0.220:7655}"
PULSE_TOKEN="${PULSE_TOKEN:-}"
AGENT_NAMESPACE="${AGENT_NAMESPACE:-pulse-agent}"
ENABLE_HOST="${ENABLE_HOST:-true}"
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

log_info "Installing Pulse agent for Kubernetes..."
log_info "  Pulse URL: $PULSE_URL"
log_info "  Namespace: $AGENT_NAMESPACE"
log_info "  Enable Host: $ENABLE_HOST"
log_info "  Enable Kubernetes: $ENABLE_KUBERNETES"
echo

# Create namespace
log_info "Creating namespace: $AGENT_NAMESPACE"
kubectl create namespace "$AGENT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create secret
log_info "Creating secret for API token..."
kubectl create secret generic pulse-agent-token \
  --from-literal=token="$PULSE_TOKEN" \
  -n "$AGENT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create ServiceAccount
log_info "Creating ServiceAccount..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pulse-agent
  namespace: $AGENT_NAMESPACE
EOF

# Create ClusterRole
log_info "Creating ClusterRole..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pulse-agent
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "services", "namespaces", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["nodes", "pods"]
  verbs: ["get", "list"]
EOF

# Create ClusterRoleBinding
log_info "Creating ClusterRoleBinding..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pulse-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pulse-agent
subjects:
- kind: ServiceAccount
  name: pulse-agent
  namespace: $AGENT_NAMESPACE
EOF

# Create DaemonSet
log_info "Creating DaemonSet..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: pulse-agent
  namespace: $AGENT_NAMESPACE
spec:
  selector:
    matchLabels:
      app: pulse-agent
  template:
    metadata:
      labels:
        app: pulse-agent
    spec:
      serviceAccountName: pulse-agent
      initContainers:
      - name: download-agent
        image: alpine:3.20
        command:
        - /bin/sh
        - -c
        - |
          apk add --no-cache curl
          mkdir -p /agent-bin
          ARCH=\$(uname -m)
          case \$ARCH in
            x86_64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            armv7l|armhf) ARCH="armv7" ;;
            armv6l) ARCH="armv6" ;;
            i386|i686) ARCH="386" ;;
            *) ARCH="amd64" ;;
          esac
          curl -fsSL "${PULSE_URL}/download/pulse-agent?arch=linux-\$ARCH" -o /agent-bin/pulse-agent
          chmod +x /agent-bin/pulse-agent
        volumeMounts:
        - name: agent-bin
          mountPath: /agent-bin
      containers:
      - name: pulse-agent
        image: alpine:3.20
        command:
        - /bin/sh
        - -c
        - |
          /agent-bin/pulse-agent \
            --url "${PULSE_URL}" \
            --token "\${PULSE_TOKEN}" \
            --enable-kubernetes \
            --enable-host \
            --interval 30s
        env:
        - name: PULSE_URL
          value: "$PULSE_URL"
        - name: PULSE_TOKEN
          valueFrom:
            secretKeyRef:
              name: pulse-agent-token
              key: token
        - name: PULSE_ENABLE_KUBERNETES
          value: "$ENABLE_KUBERNETES"
        - name: PULSE_ENABLE_HOST
          value: "$ENABLE_HOST"
        - name: PULSE_INTERVAL
          value: "30s"
        - name: PULSE_TOKEN
          valueFrom:
            secretKeyRef:
              name: pulse-agent-token
              key: token
        volumeMounts:
        - name: agent-bin
          mountPath: /agent-bin
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 9191
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /readyz
            port: 9191
          initialDelaySeconds: 10
          periodSeconds: 10
      volumes:
      - name: agent-bin
        emptyDir: {}
EOF

log_success "Pulse agent DaemonSet created!"
echo
log_info "Checking pod status..."
sleep 5
kubectl get pods -n "$AGENT_NAMESPACE"

echo
log_success "=========================================="
log_success "Installation complete!"
log_success "=========================================="
echo
log_info "Next steps:"
log_info "1. Check pod status: kubectl get pods -n $AGENT_NAMESPACE"
log_info "2. View logs: kubectl logs -n $AGENT_NAMESPACE -l app=pulse-agent"
log_info "3. Check Pulse UI: $PULSE_URL → Dashboard"
echo
log_info "Your Kubernetes cluster should appear in Pulse within a few minutes."

