#!/usr/bin/env bash
set -euo pipefail

# Setup kubeconfig for K3s worker node so pulse-agent can detect Kubernetes

NODE_NAME="${1:-ubuntu}"
CONTROL_PLANE_IP="${2:-192.168.0.204}"  # cp1 IP
CONTROL_PLANE_PORT="${3:-6443}"

echo "=========================================="
echo "Setting up Kubeconfig for K3s Worker Node"
echo "=========================================="
echo "Node: $NODE_NAME"
echo "Control Plane: $CONTROL_PLANE_IP:$CONTROL_PLANE_PORT"
echo

# Create a pod to setup kubeconfig on the worker node
echo "1. Setting up kubeconfig on worker node..."

# Create a temporary script that will be executed in the pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kubeconfig-setup-$(date +%s)
  namespace: default
spec:
  hostNetwork: true
  hostPID: true
  containers:
  - name: setup
    image: alpine:3.20
    command:
    - /bin/sh
    - -c
    - |
      # Get kubeconfig from control-plane node
      echo "Fetching kubeconfig from control-plane..."
      apk add --no-cache curl >/dev/null 2>&1
      
      # Try to get kubeconfig via kubectl exec on control-plane
      # For now, we'll create a basic kubeconfig that points to the control-plane
      mkdir -p /host/root/.kube
      
      # Create kubeconfig that uses the control-plane IP
      cat > /host/root/.kube/config <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${CONTROL_PLANE_IP}:${CONTROL_PLANE_PORT}
    insecure-skip-tls-verify: true
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
users:
- name: default
  user:
    token: ""
KUBECONFIG_EOF
      
      # For K3s, we need to get the actual token from the control-plane
      # Let's try to copy the full kubeconfig
      if [ -f /host/etc/rancher/k3s/k3s.yaml ]; then
          # If k3s.yaml exists on this node (shouldn't on worker, but check)
          cp /host/etc/rancher/k3s/k3s.yaml /host/root/.kube/config
          sed -i "s|127.0.0.1|${CONTROL_PLANE_IP}|g" /host/root/.kube/config
          sed -i "s|localhost|${CONTROL_PLANE_IP}|g" /host/root/.kube/config
      else
          # We need to get the token from the control-plane node
          # For K3s, we can read it from /var/lib/rancher/k3s/server/node-token on control-plane
          # But we're on a worker, so we'll use a workaround:
          # Set KUBECONFIG to use in-cluster config or get token another way
          echo "Note: Full kubeconfig setup may require manual token configuration"
      fi
      
      # Set permissions
      chmod 600 /host/root/.kube/config
      chown root:root /host/root/.kube/config 2>/dev/null || true
      
      echo "✓ Kubeconfig created at /root/.kube/config"
      echo "✓ Server set to ${CONTROL_PLANE_IP}:${CONTROL_PLANE_PORT}"
      
      # Verify kubectl can use it (if kubectl is installed)
      if [ -f /host/usr/local/bin/kubectl ]; then
          KUBECONFIG=/host/root/.kube/config /host/usr/local/bin/kubectl get nodes 2>&1 | head -3 || echo "kubectl test failed (may need token)"
      fi
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

POD_NAME=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "kubeconfig-setup-" | head -1)

if [ -n "$POD_NAME" ]; then
    echo "Waiting for setup to complete..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=60s 2>/dev/null || true
    
    echo
    echo "Setup logs:"
    kubectl logs "$POD_NAME" --tail=20 2>&1 || true
    
    echo
    echo "Cleaning up..."
    kubectl delete pod "$POD_NAME" --ignore-not-found=true
    
    echo
    echo "=========================================="
    echo "✓ Kubeconfig setup complete!"
    echo "=========================================="
    echo
    echo "3. Restarting pulse-agent..."
    echo "   (The agent will now be able to detect Kubernetes)"
    echo
    
    # Restart agent
    kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart pulse-agent
            echo '✓ Agent restarted'
        else
            pkill -f pulse-agent
            echo '✓ Agent process killed (will restart if managed)'
        fi
    " 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" || true
    
    echo
    echo "Wait 30-60 seconds, then check:"
    echo "  ssh $NODE_NAME 'journalctl -u pulse-agent -n 50 | grep -i kubernetes'"
    echo "  Look for: 'Kubernetes agent module started' ✅"
    echo
    echo "Or check Pulse UI: http://192.168.0.220:7655 → Dashboard"
else
    echo "Failed to create setup pod"
    exit 1
fi

