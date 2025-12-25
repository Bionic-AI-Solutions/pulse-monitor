#!/usr/bin/env bash
set -euo pipefail

# Set KUBECONFIG environment variable for pulse-agent systemd service

NODE_NAME="${1:-ubuntu}"
CONTROL_PLANE_IP="${2:-192.168.0.204}"

echo "=========================================="
echo "Setting KUBECONFIG for pulse-agent"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

# Method: Update systemd service to set KUBECONFIG pointing to control-plane
echo "Updating systemd service to use KUBECONFIG..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: set-kubeconfig-env-$(date +%s)
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
      # Create kubeconfig file
      mkdir -p /host/root/.kube
      
      # Create a basic kubeconfig that points to control-plane
      cat > /host/root/.kube/config <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${CONTROL_PLANE_IP}:6443
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
      
      chmod 600 /host/root/.kube/config
      echo "✓ Created /root/.kube/config"
      
      # Update systemd service to set KUBECONFIG env var
      if [ -f /host/etc/systemd/system/pulse-agent.service ]; then
          # Check if KUBECONFIG is already set
          if ! grep -q "KUBECONFIG" /host/etc/systemd/system/pulse-agent.service; then
              # Add KUBECONFIG after [Service]
              sed -i '/\[Service\]/a Environment="KUBECONFIG=/root/.kube/config"' /host/etc/systemd/system/pulse-agent.service
              echo "✓ Added KUBECONFIG to systemd service"
              
              # Reload systemd and restart
              systemctl --root=/host daemon-reload
              systemctl --root=/host restart pulse-agent
              echo "✓ Agent restarted"
          else
              echo "KUBECONFIG already set in service file"
              systemctl --root=/host restart pulse-agent
              echo "✓ Agent restarted"
          fi
      else
          echo "⚠ Systemd service file not found"
          echo "Agent may be running directly. Try setting KUBECONFIG manually:"
          echo "  export KUBECONFIG=/root/.kube/config"
          echo "  Then restart the agent process"
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

POD_NAME=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "set-kubeconfig-env-" | head -1)

if [ -n "$POD_NAME" ]; then
    echo "Waiting for setup..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=60s 2>/dev/null || true
    
    echo
    echo "Setup logs:"
    kubectl logs "$POD_NAME" --tail=20 2>&1 || true
    
    kubectl delete pod "$POD_NAME" --ignore-not-found=true
    
    echo
    echo "=========================================="
    echo "✓ Setup complete!"
    echo "=========================================="
    echo
    echo "Note: The kubeconfig may need an authentication token."
    echo "For K3s, you may need to copy the full kubeconfig from the control-plane:"
    echo "  ssh cp1 'cat /etc/rancher/k3s/k3s.yaml' | ssh ubuntu 'cat > ~/.kube/config'"
    echo "  (Then update the server IP in the config)"
    echo
    echo "Wait 30-60 seconds, then check:"
    echo "  ssh $NODE_NAME 'journalctl -u pulse-agent -n 50 | grep -i kubernetes'"
else
    echo "Failed to create pod"
    exit 1
fi

