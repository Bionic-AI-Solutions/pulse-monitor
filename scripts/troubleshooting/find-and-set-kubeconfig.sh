#!/usr/bin/env bash
set -euo pipefail

# Find kubeconfig and set it for pulse-agent

NODE_NAME="${1:-ubuntu}"

echo "=========================================="
echo "Finding and Setting Kubeconfig"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

echo "1. Searching for kubeconfig files..."
echo

# Search for kubeconfig files
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: find-kubeconfig-$(date +%s)
  namespace: default
spec:
  hostNetwork: true
  hostPID: true
  containers:
  - name: find
    image: alpine:3.20
    command:
    - /bin/sh
    - -c
    - |
      echo "Searching for kubeconfig files..."
      echo
      
      # Check common locations
      for kube_path in "/root/.kube/config" "/etc/rancher/k3s/k3s.yaml" "/var/lib/rancher/k3s/agent/kubeconfig.yaml"; do
        if [ -f "\$kube_path" ] 2>/dev/null; then
          echo "✓ Found: \$kube_path"
          ls -lh "\$kube_path" 2>/dev/null || true
          echo
        fi
      done
      
      # Check home directories
      for kube_path in /home/*/.kube/config; do
        if [ -f "\$kube_path" ] 2>/dev/null; then
          echo "✓ Found: \$kube_path"
          ls -lh "\$kube_path" 2>/dev/null || true
          echo
        fi
      done
      
      # Also search in user home directories
      echo "Searching user home directories..."
      for user_home in /home/*; do
        if [ -d "\$user_home" ]; then
          kubeconfig="\$user_home/.kube/config"
          if [ -f "\$kubeconfig" ]; then
            echo "✓ Found: \$kubeconfig"
            ls -lh "\$kubeconfig" 2>/dev/null || true
            echo
          fi
        fi
      done
      
      # Check what user pulse-agent runs as
      echo "Checking pulse-agent process..."
      ps aux | grep pulse-agent | grep -v grep | head -1 || echo "Agent not running"
      echo
      
      # Check if agent can see kubeconfig
      echo "Testing kubeconfig access from agent's perspective..."
      if [ -f /root/.kube/config ]; then
        echo "✓ /root/.kube/config exists"
        # Try to read it
        head -5 /root/.kube/config 2>&1 | head -5
      else
        echo "✗ /root/.kube/config not found"
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

POD_NAME=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "find-kubeconfig-" | head -1)

if [ -n "$POD_NAME" ]; then
    echo "Waiting for search..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=60s 2>/dev/null || true
    
    echo
    echo "Results:"
    kubectl logs "$POD_NAME" --tail=50 2>&1 || true
    
    kubectl delete pod "$POD_NAME" --ignore-not-found=true
    
    echo
    echo "=========================================="
    echo "Next Steps"
    echo "=========================================="
    echo
    echo "If kubeconfig was found, set it explicitly:"
    echo "  ./scripts/set-kubeconfig-explicit.sh $NODE_NAME /path/to/kubeconfig"
    echo
    echo "Or manually:"
    echo "  ssh $NODE_NAME"
    echo "  export KUBECONFIG=/path/to/kubeconfig"
    echo "  export PULSE_KUBECONFIG=/path/to/kubeconfig"
    echo "  # Then restart the agent"
else
    echo "Failed to create pod"
    exit 1
fi

