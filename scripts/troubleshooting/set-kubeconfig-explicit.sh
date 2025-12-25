#!/usr/bin/env bash
set -euo pipefail

# Set KUBECONFIG or PULSE_KUBECONFIG explicitly for pulse-agent

NODE_NAME="${1:-ubuntu}"
KUBECONFIG_PATH="${2:-}"

echo "=========================================="
echo "Setting Kubeconfig for pulse-agent"
echo "=========================================="
echo "Node: $NODE_NAME"
echo

# If path not provided, try to find it
if [ -z "$KUBECONFIG_PATH" ]; then
    echo "Searching for kubeconfig..."
    
    # Try common locations
    for path in "/root/.kube/config" "/home/*/.kube/config" "/etc/rancher/k3s/k3s.yaml"; do
        if kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "test -f $path" 2>/dev/null; then
            KUBECONFIG_PATH="$path"
            echo "Found kubeconfig at: $path"
            break
        fi
    done
    
    if [ -z "$KUBECONFIG_PATH" ]; then
        echo "⚠ Kubeconfig not found in standard locations"
        echo "Please provide the path: $0 $NODE_NAME /path/to/kubeconfig"
        exit 1
    fi
fi

echo "Using kubeconfig: $KUBECONFIG_PATH"
echo

# Update systemd service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: set-kubeconfig-$(date +%s)
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
      if [ -f /host/etc/systemd/system/pulse-agent.service ]; then
          # Check if already set
          if grep -q "KUBECONFIG\|PULSE_KUBECONFIG" /host/etc/systemd/system/pulse-agent.service; then
              echo "KUBECONFIG or PULSE_KUBECONFIG already set"
              # Update it
              sed -i 's|Environment="KUBECONFIG=.*|Environment="KUBECONFIG=${KUBECONFIG_PATH}"|' /host/etc/systemd/system/pulse-agent.service
              sed -i 's|Environment="PULSE_KUBECONFIG=.*|Environment="PULSE_KUBECONFIG=${KUBECONFIG_PATH}"|' /host/etc/systemd/system/pulse-agent.service
          else
              # Add it
              sed -i '/\[Service\]/a Environment="KUBECONFIG=${KUBECONFIG_PATH}"' /host/etc/systemd/system/pulse-agent.service
              sed -i '/\[Service\]/a Environment="PULSE_KUBECONFIG=${KUBECONFIG_PATH}"' /host/etc/systemd/system/pulse-agent.service
          fi
          
          echo "✓ Updated systemd service"
          systemctl --root=/host daemon-reload
          systemctl --root=/host restart pulse-agent
          echo "✓ Agent restarted"
      else
          echo "⚠ Systemd service not found"
          echo "Agent may be running directly. Set environment variable manually:"
          echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
          echo "  export PULSE_KUBECONFIG=${KUBECONFIG_PATH}"
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

POD_NAME=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "set-kubeconfig-" | head -1)

if [ -n "$POD_NAME" ]; then
    echo "Waiting for setup..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=60s 2>/dev/null || true
    
    echo
    echo "Setup logs:"
    kubectl logs "$POD_NAME" --tail=15 2>&1 || true
    
    kubectl delete pod "$POD_NAME" --ignore-not-found=true
    
    echo
    echo "=========================================="
    echo "✓ Setup complete!"
    echo "=========================================="
    echo
    echo "Wait 30-60 seconds, then check:"
    echo "  ssh $NODE_NAME 'journalctl -u pulse-agent -n 50 | grep -i kubernetes'"
    echo "  Look for: 'Kubernetes agent module started' ✅"
else
    echo "Failed to create pod"
    exit 1
fi

