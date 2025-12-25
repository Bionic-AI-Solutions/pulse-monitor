#!/usr/bin/env bash
set -euo pipefail

# Verify Kubernetes detection is working

NODE_NAME="${1:-cp1}"

echo "=========================================="
echo "Verifying Kubernetes Detection"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

echo "1. Checking kubectl installation..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    if command -v kubectl >/dev/null 2>&1; then
        echo '✓ kubectl is installed'
        kubectl version --client 2>&1 | head -2
    else
        echo '✗ kubectl not found'
    fi
" 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" || true

echo
echo "2. Checking agent process..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    ps aux | grep pulse-agent | grep -v grep | head -1
" 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" || true

echo
echo "3. Checking agent logs for Kubernetes detection..."
echo "   (This may take a moment to retrieve logs)"
echo

# Try to get logs via journalctl or log file
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u pulse-agent --no-pager -n 30 2>&1 | grep -i 'kubernetes\|error\|started' || echo 'No relevant log entries found'
    elif [ -f /var/log/pulse-agent.log ]; then
        tail -30 /var/log/pulse-agent.log 2>&1 | grep -i 'kubernetes\|error\|started' || echo 'No relevant log entries found'
    else
        echo 'Cannot access logs (journalctl not available, no log file)'
        echo 'Try: ssh $NODE_NAME journalctl -u pulse-agent -f'
    fi
" 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" | head -20 || true

echo
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo
echo "If you see 'Kubernetes agent module started' in the logs,"
echo "then Kubernetes detection is working!"
echo
echo "Check Pulse UI: http://192.168.0.220:7655 → Dashboard"
echo "Your Kubernetes cluster should appear within 1-2 minutes."
echo
echo "If not working, check logs manually:"
echo "  ssh $NODE_NAME 'journalctl -u pulse-agent -f'"
echo

