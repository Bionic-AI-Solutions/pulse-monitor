#!/usr/bin/env bash
set -euo pipefail

# Fix Kubernetes detection for pulse-agent on K3s nodes

NODE_NAME="${1:-cp1}"
K3S_CONFIG="/etc/rancher/k3s/k3s.yaml"
KUBECONFIG_DEST="/root/.kube/config"

echo "=========================================="
echo "Fixing Kubernetes Detection"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

# Check if k3s config exists
echo "1. Checking for K3s kubeconfig..."
if kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "test -f $K3S_CONFIG" 2>/dev/null; then
    echo "   ✓ Found $K3S_CONFIG"
    
    # Copy kubeconfig to standard location
    echo "2. Copying kubeconfig to $KUBECONFIG_DEST..."
    kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
        mkdir -p /root/.kube
        cp $K3S_CONFIG $KUBECONFIG_DEST
        chmod 600 $KUBECONFIG_DEST
        echo '✓ Kubeconfig copied'
    " 2>&1 | grep -v "Unable to use a TTY" || true
    
    # Update kubeconfig to use correct server (replace localhost with node IP)
    echo "3. Updating kubeconfig server address..."
    NODE_IP=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    if [ -n "$NODE_IP" ]; then
        kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
            sed -i 's|127.0.0.1|$NODE_IP|g' $KUBECONFIG_DEST
            sed -i 's|localhost|$NODE_IP|g' $KUBECONFIG_DEST
            echo '✓ Updated server address to $NODE_IP'
        " 2>&1 | grep -v "Unable to use a TTY" || true
    fi
    
    # Restart agent
    echo "4. Restarting pulse-agent..."
    kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart pulse-agent
            echo '✓ Agent restarted'
        else
            # Find and kill agent process, it will restart if managed
            pkill -f pulse-agent || true
            echo '✓ Agent process killed (will restart if managed)'
        fi
    " 2>&1 | grep -v "Unable to use a TTY" || true
    
    echo
    echo "=========================================="
    echo "✓ Kubernetes detection should now work!"
    echo "=========================================="
    echo
    echo "Wait 30-60 seconds, then check Pulse UI."
    echo "The Kubernetes cluster should appear in the dashboard."
    echo
    echo "To verify, check agent logs:"
    echo "  ssh $NODE_NAME 'journalctl -u pulse-agent -f'"
    echo "  (Look for 'Kubernetes agent module started')"
    
else
    echo "   ✗ $K3S_CONFIG not found"
    echo
    echo "Alternative: Install kubectl on the node"
    echo "  ssh $NODE_NAME"
    echo "  curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    echo "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    echo "  sudo systemctl restart pulse-agent"
fi

