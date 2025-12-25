# Kubernetes Agent Setup Guide

This guide explains how to install the Pulse agent to monitor your Kubernetes cluster.

## Overview

The Pulse unified agent (`pulse-agent`) can monitor Kubernetes clusters by:
- Running as a DaemonSet on each node
- Running as a Deployment on a single node
- Running directly on a cluster node

The agent automatically detects if it's running in Kubernetes and enables Kubernetes monitoring.

## Prerequisites

1. **Pulse server running** (you have this at `http://192.168.0.220:7655`)
2. **API token** from Pulse (see below)
3. **Kubernetes access** - The agent needs access to the Kubernetes API

## Step 1: Create API Token

1. **Access Pulse UI:**
   ```
   http://192.168.0.220:7655
   ```

2. **Navigate to Settings:**
   - Go to **Settings → Security → API Tokens**
   - Click **"Create Token"** or **"Add Token"**

3. **Configure Token:**
   - **Name**: e.g., "kubernetes-agent"
   - **Scopes**: Select appropriate scopes (at minimum `monitoring:write`)
   - **Expiration**: Optional (leave blank for no expiration)

4. **Copy the token** - You'll need this for the agent installation

## Step 2: Install Agent

### Option A: Install via UI (Recommended)

1. **Go to Settings → Agents**
2. **Click "Install New Agent"**
3. **Select "Kubernetes"** or **"Linux"** (if installing on a node)
4. **Copy the generated command** - It will include your Pulse URL and token

### Option B: Manual Installation

#### On a Kubernetes Node (systemd)

```bash
# Replace <YOUR-TOKEN> with your API token
curl -fsSL http://192.168.0.220:7655/install.sh | \
  bash -s -- \
    --url http://192.168.0.220:7655 \
    --token <YOUR-TOKEN> \
    --enable-kubernetes
```

#### As Kubernetes DaemonSet (Recommended for Multi-Node)

Create a DaemonSet to run the agent on all nodes:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: pulse-agent
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: pulse-agent
  template:
    metadata:
      labels:
        app: pulse-agent
    spec:
      serviceAccountName: pulse-agent
      containers:
      - name: pulse-agent
        image: rcourtman/pulse-agent:latest
        env:
        - name: PULSE_URL
          value: "http://192.168.0.220:7655"
        - name: PULSE_TOKEN
          valueFrom:
            secretKeyRef:
              name: pulse-agent-token
              key: token
        - name: PULSE_ENABLE_KUBERNETES
          value: "true"
        - name: PULSE_ENABLE_HOST
          value: "true"
        volumeMounts:
        - name: kubeconfig
          mountPath: /root/.kube
          readOnly: true
      volumes:
      - name: kubeconfig
        hostPath:
          path: /root/.kube
          type: Directory
---
apiVersion: v1
kind: Secret
metadata:
  name: pulse-agent-token
  namespace: kube-system
type: Opaque
stringData:
  token: <YOUR-TOKEN>
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pulse-agent
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pulse-agent
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "services", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pulse-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pulse-agent
subjects:
- kind: ServiceAccount
  name: pulse-agent
  namespace: kube-system
```

Apply with:
```bash
kubectl apply -f pulse-agent-daemonset.yaml
```

#### As Kubernetes Deployment (Single Instance)

For a single agent instance monitoring the cluster:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pulse-agent
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pulse-agent
  template:
    metadata:
      labels:
        app: pulse-agent
    spec:
      serviceAccountName: pulse-agent
      containers:
      - name: pulse-agent
        image: rcourtman/pulse-agent:latest
        env:
        - name: PULSE_URL
          value: "http://192.168.0.220:7655"
        - name: PULSE_TOKEN
          valueFrom:
            secretKeyRef:
              name: pulse-agent-token
              key: token
        - name: PULSE_ENABLE_KUBERNETES
          value: "true"
        - name: PULSE_ENABLE_HOST
          value: "false"  # Disable host metrics for cluster monitoring
---
# Include the Secret, ServiceAccount, ClusterRole, and ClusterRoleBinding from above
```

## Step 3: Verify Installation

### Check Agent Status

1. **In Pulse UI:**
   - Go to **Dashboard** or **Settings → Agents**
   - You should see your Kubernetes cluster appear
   - Check for agent status (connected/disconnected)

2. **Check Pod Status:**
   ```bash
   # If installed as DaemonSet/Deployment
   kubectl get pods -n kube-system -l app=pulse-agent
   
   # Check logs
   kubectl logs -n kube-system -l app=pulse-agent --tail=50
   ```

3. **Check Agent Connection:**
   ```bash
   # Test from agent pod
   kubectl exec -n kube-system <pulse-agent-pod> -- \
     curl -H "X-API-Token: <YOUR-TOKEN>" \
     http://192.168.0.220:7655/api/health
   ```

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PULSE_URL` | Pulse server URL | `http://localhost:7655` |
| `PULSE_TOKEN` | API token | *(required)* |
| `PULSE_ENABLE_KUBERNETES` | Enable K8s monitoring | `auto-detect` |
| `PULSE_ENABLE_HOST` | Enable host metrics | `true` |
| `PULSE_ENABLE_DOCKER` | Enable Docker metrics | `auto-detect` |
| `PULSE_INTERVAL` | Reporting interval | `30s` |

### Command Line Flags

```bash
pulse-agent \
  --url http://192.168.0.220:7655 \
  --token <YOUR-TOKEN> \
  --enable-kubernetes \
  --interval 30s
```

## What Gets Monitored

Once the agent is connected, Pulse will monitor:

- **Cluster Health**: Overall cluster status
- **Nodes**: CPU, memory, disk usage, conditions
- **Pods**: Status, resource usage, restarts
- **Deployments**: Replicas, available/ready status
- **Services**: Endpoints, selectors
- **Namespaces**: Resource counts
- **DaemonSets/StatefulSets**: Status and health

## Troubleshooting

### Agent Not Appearing in Pulse

1. **Check token:**
   ```bash
   # Verify token is correct
   curl -H "X-API-Token: <YOUR-TOKEN>" \
     http://192.168.0.220:7655/api/health
   ```

2. **Check network connectivity:**
   ```bash
   # From agent pod/node
   curl http://192.168.0.220:7655/api/health
   ```

3. **Check agent logs:**
   ```bash
   kubectl logs -n kube-system -l app=pulse-agent
   ```

### Kubernetes Access Issues

If the agent can't access Kubernetes API:

1. **Check RBAC permissions:**
   ```bash
   kubectl auth can-i get nodes --as=system:serviceaccount:kube-system:pulse-agent
   kubectl auth can-i list pods --as=system:serviceaccount:kube-system:pulse-agent
   ```

2. **Verify ServiceAccount exists:**
   ```bash
   kubectl get serviceaccount pulse-agent -n kube-system
   ```

3. **Check ClusterRoleBinding:**
   ```bash
   kubectl get clusterrolebinding pulse-agent
   ```

### Agent Pod CrashLoopBackOff

1. **Check pod logs:**
   ```bash
   kubectl logs -n kube-system <pulse-agent-pod> --previous
   ```

2. **Check pod events:**
   ```bash
   kubectl describe pod -n kube-system <pulse-agent-pod>
   ```

3. **Common issues:**
   - Missing or invalid token
   - Network connectivity to Pulse server
   - RBAC permissions missing
   - Invalid PULSE_URL

## Quick Install Script

Here's a complete script to install the agent as a DaemonSet:

```bash
#!/bin/bash
set -e

PULSE_URL="${PULSE_URL:-http://192.168.0.220:7655}"
PULSE_TOKEN="${PULSE_TOKEN:-}"

if [ -z "$PULSE_TOKEN" ]; then
    echo "Error: PULSE_TOKEN environment variable is required"
    echo "Get your token from: $PULSE_URL → Settings → Security → API Tokens"
    exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace pulse-agent --dry-run=client -o yaml | kubectl apply -f -

# Create secret
kubectl create secret generic pulse-agent-token \
  --from-literal=token="$PULSE_TOKEN" \
  -n pulse-agent --dry-run=client -o yaml | kubectl apply -f -

# Create ServiceAccount
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pulse-agent
  namespace: pulse-agent
EOF

# Create ClusterRole
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pulse-agent
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "services", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets", "replicasets"]
  verbs: ["get", "list", "watch"]
EOF

# Create ClusterRoleBinding
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pulse-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pulse-agent
subjects:
- kind: ServiceAccount
  name: pulse-agent
  namespace: pulse-agent
EOF

# Create DaemonSet
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: pulse-agent
  namespace: pulse-agent
spec:
  selector:
    matchLabels:
      app: pulse-agent
  template:
    metadata:
      labels:
        app: pulse-agent
    spec:
      serviceAccountName: pulse-agent
      containers:
      - name: pulse-agent
        image: rcourtman/pulse-agent:latest
        env:
        - name: PULSE_URL
          value: "$PULSE_URL"
        - name: PULSE_TOKEN
          valueFrom:
            secretKeyRef:
              name: pulse-agent-token
              key: token
        - name: PULSE_ENABLE_KUBERNETES
          value: "true"
        - name: PULSE_ENABLE_HOST
          value: "true"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "500m"
EOF

echo "✅ Pulse agent DaemonSet created!"
echo "Check status with: kubectl get pods -n pulse-agent"
```

Save as `install-pulse-agent.sh` and run:
```bash
export PULSE_TOKEN="your-token-here"
bash install-pulse-agent.sh
```

## Next Steps

After the agent is installed and connected:

1. **View Cluster in Dashboard**: Your Kubernetes cluster should appear in the Pulse dashboard
2. **Set Up Alerts**: Configure alerts for cluster/node/pod issues
3. **Monitor Resources**: View resource usage, pod status, and cluster health
4. **Review Metrics**: Check historical metrics and trends

## Additional Resources

- [Unified Agent Documentation](docs/UNIFIED_AGENT.md)
- [Kubernetes Documentation](docs/KUBERNETES.md)
- [Pulse API Documentation](docs/API.md)

