#!/usr/bin/env bash
set -euo pipefail

# Fix Kubernetes detection for pulse-agent on K3s by setting KUBECONFIG

NODE_NAME="${1:-cp1}"
K3S_CONFIG="/etc/rancher/k3s/k3s.yaml"

echo "=========================================="
echo "Fixing Kubernetes Detection for K3s"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

# Method 1: Update systemd service to set KUBECONFIG
echo "Method 1: Updating systemd service with KUBECONFIG..."

kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    if [ -f /etc/systemd/system/pulse-agent.service ]; then
        # Check if KUBECONFIG is already set
        if grep -q 'KUBECONFIG' /etc/systemd/system/pulse-agent.service; then
            echo 'KUBECONFIG already set in service file'
        else
            # Add KUBECONFIG environment variable
            if [ -f $K3S_CONFIG ]; then
                # Insert Environment line after [Service]
                sed -i '/\[Service\]/a Environment=\"KUBECONFIG='$K3S_CONFIG'\"' /etc/systemd/system/pulse-agent.service
                echo '✓ Added KUBECONFIG to service file'
                systemctl daemon-reload
                systemctl restart pulse-agent
                echo '✓ Agent restarted'
            else
                echo '✗ K3s config not found at $K3S_CONFIG'
                echo 'Trying alternative locations...'
                # Try to find k3s.yaml
                if [ -f /var/lib/rancher/k3s/server/node-token ]; then
                    # This is a server node, config should be at /etc/rancher/k3s/k3s.yaml
                    echo 'Found K3s server, but config not at expected location'
                fi
            fi
        fi
    else
        echo '✗ Systemd service file not found'
        echo 'Agent may be running directly (not via systemd)'
    fi
" 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" || true

echo
echo "Method 2: Installing kubectl (alternative solution)..."
echo "This allows the agent to auto-detect Kubernetes via kubectl command"
echo
echo "To install kubectl on the node, SSH and run:"
echo "  ssh $NODE_NAME"
echo "  curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
echo "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
echo "  sudo systemctl restart pulse-agent"
echo

echo "Method 3: Using --kubeconfig flag (if agent supports it)..."
echo "Update the agent command to include: --kubeconfig=$K3S_CONFIG"
echo

echo "=========================================="
echo "Verification"
echo "=========================================="
echo "Wait 30-60 seconds, then check:"
echo "1. Agent logs: ssh $NODE_NAME 'journalctl -u pulse-agent -n 50'"
echo "2. Look for: 'Kubernetes agent module started'"
echo "3. Check Pulse UI: http://192.168.0.220:7655 → Dashboard"
echo

