#!/usr/bin/env bash
set -euo pipefail

# Install kubectl on a K3s node to enable Kubernetes detection

NODE_NAME="${1:-cp1}"

echo "=========================================="
echo "Installing kubectl on K3s Node"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

echo "This script will:"
echo "1. Download kubectl binary"
echo "2. Install it to /usr/local/bin/kubectl"
echo "3. Restart pulse-agent"
echo

# Create a pod that will install kubectl on the host
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kubectl-installer-$(date +%s)
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
      apk add --no-cache curl
      
      # Download kubectl
      KUBECTL_VERSION=\$(curl -L -s https://dl.k8s.io/release/stable.txt)
      echo "Downloading kubectl \${KUBECTL_VERSION}..."
      curl -LO "https://dl.k8s.io/release/\${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
      
      # Install to host
      chmod +x kubectl
      cp kubectl /host/usr/local/bin/kubectl
      
      # Verify installation
      /host/usr/local/bin/kubectl version --client --short
      
      echo "✓ kubectl installed successfully"
      
      # Restart pulse-agent if running
      if pgrep -f pulse-agent >/dev/null; then
          echo "Restarting pulse-agent..."
          pkill -f pulse-agent || true
          # If managed by systemd, use systemctl
          if command -v systemctl >/dev/null 2>&1; then
              systemctl restart pulse-agent 2>/dev/null || true
          fi
      fi
      
      echo "✓ Done"
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

POD_NAME=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "kubectl-installer-" | head -1)

if [ -n "$POD_NAME" ]; then
    echo "Waiting for installation to complete..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=120s 2>/dev/null || true
    
    echo
    echo "Installation logs:"
    kubectl logs "$POD_NAME" --tail=20 2>&1 || true
    
    echo
    echo "Cleaning up..."
    kubectl delete pod "$POD_NAME" --ignore-not-found=true
    
    echo
    echo "=========================================="
    echo "✓ kubectl installation complete!"
    echo "=========================================="
    echo
    echo "The agent should now detect Kubernetes."
    echo "Wait 30-60 seconds, then check:"
    echo "1. Agent logs: ssh $NODE_NAME 'journalctl -u pulse-agent -n 50'"
    echo "2. Look for: 'Kubernetes agent module started'"
    echo "3. Check Pulse UI: http://192.168.0.220:7655 → Dashboard"
else
    echo "Failed to create installer pod"
    exit 1
fi

