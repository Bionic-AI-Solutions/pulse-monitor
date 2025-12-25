#!/usr/bin/env bash
set -euo pipefail

# Fix RBAC permissions for pulse-agent running on node

NODE_NAME="${1:-ubuntu}"

echo "=========================================="
echo "Fixing RBAC Permissions for pulse-agent"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

echo "The agent is running on the node using kubeconfig."
echo "The kubeconfig user might have limited permissions."
echo
echo "Options:"
echo "1. Grant ClusterRole permissions to the kubeconfig user"
echo "2. Use ServiceAccount token instead (if agent supports it)"
echo "3. Check if namespace filters are set"
echo

# Check current kubeconfig user
echo "1. Checking kubeconfig user..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    if [ -f /host/root/.kube/config ]; then
        echo 'Current context:'
        grep -A 3 'current-context:' /host/root/.kube/config | head -3
        echo
        echo 'User in context:'
        grep -A 10 'contexts:' /host/root/.kube/config | grep -A 5 'user:' | head -5
    fi
" 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" | grep -v "Creating debugging" || true

echo
echo "2. Creating ClusterRoleBinding for kubeconfig user..."
echo

# Get the user from kubeconfig context
USER_NAME=$(kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    if [ -f /host/root/.kube/config ]; then
        grep -A 10 'contexts:' /host/root/.kube/config | grep 'user:' | head -1 | awk '{print \$2}' | tr -d '\"'
    fi
" 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" | grep -v "Creating debugging" | tail -1)

if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "default" ]; then
    echo "Found user: $USER_NAME"
    echo
    echo "Creating ClusterRoleBinding to grant pulse-agent permissions..."
    
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pulse-agent-node-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pulse-agent
subjects:
- kind: User
  name: $USER_NAME
  apiGroup: rbac.authorization.k8s.io
EOF
    
    echo "✓ ClusterRoleBinding created"
else
    echo "⚠ Could not determine user from kubeconfig"
    echo
    echo "Alternative: Create ClusterRoleBinding for a specific user"
    echo "  kubectl create clusterrolebinding pulse-agent-node-user \\"
    echo "    --clusterrole=pulse-agent \\"
    echo "    --user=<kubeconfig-user-name>"
fi

echo
echo "3. Checking if namespace filters are set in agent config..."
kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
    ps aux | grep pulse-agent | grep -v grep | grep -o 'kube-include-namespace[^ ]*' || echo 'No namespace filters found in command'
" 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" | grep -v "Creating debugging" || true

echo
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo
echo "1. If ClusterRoleBinding was created, restart the agent:"
echo "   ssh $NODE_NAME 'sudo systemctl restart pulse-agent'"
echo
echo "2. Wait 30-60 seconds, then check Pulse UI"
echo "   All namespaces should now be visible"
echo
echo "3. If still only seeing default namespace, check:"
echo "   - Agent logs for namespace filter settings"
echo "   - Kubeconfig user permissions"
echo "   - Whether agent has --kube-include-namespace flags set"

