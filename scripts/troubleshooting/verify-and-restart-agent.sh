#!/usr/bin/env bash
set -euo pipefail

# Verify kubeconfig and restart pulse-agent

NODE_NAME="${1:-ubuntu}"

echo "=========================================="
echo "Verifying Kubeconfig and Restarting Agent"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: verify-kubeconfig-$(date +%s)
  namespace: default
spec:
  hostNetwork: true
  hostPID: true
  containers:
  - name: verify
    image: alpine:3.20
    command:
    - /bin/sh
    - -c
    - |
      echo "1. Checking kubeconfig file..."
      if [ -f /host/root/.kube/config ]; then
          echo "✓ /root/.kube/config exists"
          ls -lh /host/root/.kube/config
          echo
          echo "Checking kubeconfig content..."
          head -10 /host/root/.kube/config
          echo
      else
          echo "✗ /root/.kube/config not found"
          exit 1
      fi
      
      echo "2. Testing kubectl with kubeconfig..."
      if [ -f /host/usr/local/bin/kubectl ]; then
          KUBECONFIG=/host/root/.kube/config /host/usr/local/bin/kubectl get nodes 2>&1 | head -5 || echo "kubectl test failed (may need auth)"
      else
          echo "kubectl not found"
      fi
      echo
      
      echo "3. Restarting pulse-agent..."
      # Find how agent is running
      if [ -f /host/etc/systemd/system/pulse-agent.service ]; then
          echo "Agent managed by systemd"
          systemctl --root=/host restart pulse-agent
          echo "✓ Agent restarted via systemctl"
      else
          echo "Agent not managed by systemd, killing process..."
          pkill -f pulse-agent || echo "No agent process found"
          echo "✓ Agent process killed (will restart if managed)"
      fi
      echo
      
      echo "4. Waiting a moment, then checking agent status..."
      sleep 3
      ps aux | grep pulse-agent | grep -v grep | head -1 || echo "Agent not running"
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

POD_NAME=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "verify-kubeconfig-" | head -1)

if [ -n "$POD_NAME" ]; then
    echo "Waiting for verification..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=60s 2>/dev/null || true
    
    echo
    echo "Results:"
    kubectl logs "$POD_NAME" --tail=50 2>&1 || true
    
    kubectl delete pod "$POD_NAME" --ignore-not-found=true
    
    echo
    echo "=========================================="
    echo "✓ Verification complete!"
    echo "=========================================="
    echo
    echo "Wait 30-60 seconds, then check agent logs:"
    echo "  ssh $NODE_NAME 'journalctl -u pulse-agent -n 50 | grep -i kubernetes'"
    echo
    echo "Look for: 'Kubernetes agent module started' ✅"
    echo
    echo "If still not working, check:"
    echo "  1. Kubeconfig has valid server address (not 127.0.0.1)"
    echo "  2. Kubeconfig has authentication token/certificate"
    echo "  3. Agent can reach the Kubernetes API server"
else
    echo "Failed to create pod"
    exit 1
fi

