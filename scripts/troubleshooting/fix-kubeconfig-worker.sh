#!/usr/bin/env bash
set -euo pipefail

# Fix kubeconfig for worker node - simpler approach using kubectl

NODE_NAME="${1:-ubuntu}"
CONTROL_PLANE_IP="${2:-192.168.0.204}"

echo "=========================================="
echo "Setting up Kubeconfig for Worker Node"
echo "=========================================="
echo "Node: $NODE_NAME"
echo "Control Plane IP: $CONTROL_PLANE_IP"
echo

# Get the current kubeconfig from the cluster (we're running kubectl from outside)
echo "1. Extracting kubeconfig from cluster..."

# Get kubeconfig content using kubectl config view
KUBECONFIG_YAML=$(kubectl config view --raw --minify 2>/dev/null || echo "")

if [ -z "$KUBECONFIG_YAML" ]; then
    echo "✗ Could not extract kubeconfig"
    echo "Trying alternative method..."
    
    # Alternative: Create a basic kubeconfig
    KUBECONFIG_YAML="apiVersion: v1
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
    token: \"\"
"
fi

# Update server address to use control-plane IP
KUBECONFIG_YAML=$(echo "$KUBECONFIG_YAML" | sed "s|server:.*|server: https://${CONTROL_PLANE_IP}:6443|g" | sed "s|127.0.0.1|${CONTROL_PLANE_IP}|g" | sed "s|localhost|${CONTROL_PLANE_IP}|g")

echo "✓ Kubeconfig prepared"
echo

# Create pod to setup kubeconfig
echo "2. Installing kubeconfig on worker node..."

# Save kubeconfig to temp file first
TEMP_KUBECONFIG=$(mktemp)
echo "$KUBECONFIG_YAML" > "$TEMP_KUBECONFIG"

# Base64 encode it to pass through kubectl
KUBECONFIG_B64=$(base64 -w 0 < "$TEMP_KUBECONFIG" 2>/dev/null || base64 < "$TEMP_KUBECONFIG")

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kubeconfig-fix-$(date +%s)
  namespace: default
spec:
  hostNetwork: true
  hostPID: true
  containers:
  - name: fix
    image: alpine:3.20
    command:
    - /bin/sh
    - -c
    - |
      apk add --no-cache base64 >/dev/null 2>&1
      
      # Decode and write kubeconfig
      mkdir -p /host/root/.kube
      echo '${KUBECONFIG_B64}' | base64 -d > /host/root/.kube/config
      
      # Set permissions
      chmod 600 /host/root/.kube/config
      
      echo "✓ Kubeconfig installed at /root/.kube/config"
      
      # Test if kubectl works
      if [ -f /host/usr/local/bin/kubectl ]; then
          KUBECONFIG=/host/root/.kube/config /host/usr/local/bin/kubectl get nodes 2>&1 | head -3 || echo "Note: May need authentication token"
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

rm -f "$TEMP_KUBECONFIG"

POD_NAME=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "kubeconfig-fix-" | head -1)

if [ -n "$POD_NAME" ]; then
    echo "Waiting for setup..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=60s 2>/dev/null || true
    
    echo
    echo "Setup logs:"
    kubectl logs "$POD_NAME" --tail=10 2>&1 || true
    
    kubectl delete pod "$POD_NAME" --ignore-not-found=true
    
    echo
    echo "3. Restarting pulse-agent..."
    kubectl debug node/"$NODE_NAME" -it --image=alpine:3.20 -- sh -c "
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart pulse-agent && echo '✓ Agent restarted'
        else
            pkill -f pulse-agent && echo '✓ Agent process killed'
        fi
    " 2>&1 | grep -v "Unable to use a TTY" | grep -v "All commands" | grep -v "warning:" || true
    
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

