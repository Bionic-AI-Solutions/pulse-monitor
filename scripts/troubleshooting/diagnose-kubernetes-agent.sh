#!/usr/bin/env bash
set -euo pipefail

# Diagnostic script to check why Kubernetes is not being detected

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo "=========================================="
echo "Kubernetes Agent Diagnostic Tool"
echo "=========================================="
echo

# Check which node has the agent
log_info "Checking which nodes have pulse-agent installed..."

NODES_WITH_AGENT=()
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    if kubectl debug node/"$node" -it --image=alpine:3.20 -- sh -c "test -f /usr/local/bin/pulse-agent || test -f /opt/pulse/pulse-agent || systemctl list-units | grep -q pulse-agent" 2>/dev/null; then
        NODES_WITH_AGENT+=("$node")
    fi
done

if [ ${#NODES_WITH_AGENT[@]} -eq 0 ]; then
    log_error "No nodes found with pulse-agent installed"
    echo
    log_info "To install the agent, run:"
    log_info "  ssh <node-name>"
    log_info "  curl -fsSL http://192.168.0.220:7655/install.sh | sudo bash -s -- --url http://192.168.0.220:7655 --token <TOKEN> --enable-kubernetes"
    exit 1
fi

log_success "Found agent on node(s): ${NODES_WITH_AGENT[*]}"
NODE_NAME="${NODES_WITH_AGENT[0]}"
log_info "Checking node: $NODE_NAME"
echo

# Check agent service status
log_info "1. Checking agent service status..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status pulse-agent --no-pager -l || true
    else
        echo 'systemctl not available (checking process)'
        ps aux | grep -i pulse-agent | grep -v grep || echo 'No pulse-agent process found'
    fi
" 2>&1 | head -30 || true
echo

# Check agent logs
log_info "2. Checking recent agent logs..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u pulse-agent --no-pager -n 50 2>&1 || true
    elif [ -f /var/log/pulse-agent.log ]; then
        tail -50 /var/log/pulse-agent.log 2>&1 || true
    else
        echo 'No logs found via journalctl or log file'
    fi
" 2>&1 | head -50 || true
echo

# Check Kubernetes detection prerequisites
log_info "3. Checking Kubernetes detection prerequisites..."

kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    echo 'Checking kubectl...'
    if command -v kubectl >/dev/null 2>&1; then
        echo '✓ kubectl found'
        kubectl version --client --short 2>&1 || true
    else
        echo '✗ kubectl not found in PATH'
    fi
    echo
    echo 'Checking kubeconfig...'
    if [ -f /root/.kube/config ]; then
        echo '✓ /root/.kube/config exists'
    elif [ -f /home/*/.kube/config ]; then
        echo '✓ ~/.kube/config exists (in user home)'
    else
        echo '✗ No kubeconfig found in standard locations'
    fi
    echo
    echo 'Checking KUBECONFIG env var...'
    if [ -n \"\$KUBECONFIG\" ]; then
        echo \"✓ KUBECONFIG=\$KUBECONFIG\"
    else
        echo '✗ KUBECONFIG not set'
    fi
    echo
    echo 'Checking if running in pod (service account token)...'
    if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
        echo '✓ Service account token found (running in pod)'
    else
        echo '✗ Not running in pod (no service account token)'
    fi
" 2>&1 || true
echo

# Check if agent can access Kubernetes API
log_info "4. Testing Kubernetes API access from agent node..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    apk add --no-cache curl >/dev/null 2>&1
    if command -v kubectl >/dev/null 2>&1; then
        echo 'Testing kubectl get nodes...'
        kubectl get nodes 2>&1 | head -5 || echo '✗ kubectl get nodes failed'
    else
        echo 'kubectl not available, cannot test API access'
    fi
" 2>&1 || true
echo

# Check agent configuration
log_info "5. Checking agent configuration..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    echo 'Environment variables:'
    if [ -f /etc/systemd/system/pulse-agent.service ]; then
        echo 'Service file found:'
        grep -E 'PULSE_|Environment=' /etc/systemd/system/pulse-agent.service 2>&1 || true
    fi
    echo
    echo 'Process environment (if running):'
    ps aux | grep -i pulse-agent | grep -v grep | head -1 || echo 'Agent not running'
" 2>&1 || true
echo

# Check Pulse server connectivity
log_info "6. Testing connectivity to Pulse server..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    apk add --no-cache curl >/dev/null 2>&1
    echo 'Testing connection to http://192.168.0.220:7655...'
    if curl -fsSL --connect-timeout 5 http://192.168.0.220:7655/api/health 2>&1; then
        echo '✓ Pulse server is reachable'
    else
        echo '✗ Cannot reach Pulse server'
    fi
" 2>&1 || true
echo

# Summary and recommendations
echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo
log_info "Common issues and fixes:"
echo
echo "1. kubectl not found:"
echo "   - Install kubectl on the node"
echo "   - Or set KUBECONFIG environment variable"
echo "   - Or ensure ~/.kube/config exists"
echo
echo "2. Kubernetes detection disabled:"
echo "   - Check logs for 'Kubernetes not available'"
echo "   - Ensure --enable-kubernetes flag was used during installation"
echo "   - Or set PULSE_ENABLE_KUBERNETES=true"
echo
echo "3. API access issues:"
echo "   - Verify kubectl works: kubectl get nodes"
echo "   - Check kubeconfig permissions"
echo
echo "4. Agent not running:"
echo "   - Check: systemctl status pulse-agent"
echo "   - Restart: systemctl restart pulse-agent"
echo "   - View logs: journalctl -u pulse-agent -f"
echo

