# Kubernetes Agent Troubleshooting

## Issue: Kubernetes Not Being Detected

### Problem
The Pulse agent is installed but Kubernetes is not being detected/monitored.

### Root Causes

1. **Agent not running** - Pods in ImagePullBackOff or CrashLoopBackOff
2. **Agent not installed** - No agent running at all
3. **Kubernetes detection failed** - Agent can't access Kubernetes API
4. **Wrong installation method** - Using non-existent Docker image

## Solutions

### Solution 1: Install Agent on Node (Recommended)

The **unified agent** (`pulse-agent`) is a binary, not a Docker image. Install it directly on a Kubernetes node:

```bash
# SSH to a Kubernetes node
ssh <node-name>

# Install agent
curl -fsSL http://192.168.0.220:7655/install.sh | \
  sudo bash -s -- \
    --url http://192.168.0.220:7655 \
    --token <YOUR-TOKEN> \
    --enable-kubernetes
```

**Why this works:**
- Agent runs directly on the node with full Kubernetes API access
- Auto-detects Kubernetes when `kubectl` is available or `/var/run/secrets/kubernetes.io/serviceaccount` exists
- Can monitor the entire cluster from one node

### Solution 2: Use Fixed DaemonSet Script

The updated `install-kubernetes-agent.sh` script now:
- Downloads the agent binary using an init container
- Runs the binary in an Alpine container
- Properly configures environment variables

```bash
export PULSE_TOKEN="your-token"
./scripts/install-kubernetes-agent.sh
```

### Solution 3: Manual DaemonSet Creation

Create a DaemonSet that downloads and runs the agent:

```yaml
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
      initContainers:
      - name: download-agent
        image: alpine:3.20
        command:
        - /bin/sh
        - -c
        - |
          apk add --no-cache curl
          ARCH=$(uname -m)
          case $ARCH in
            x86_64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            *) ARCH="amd64" ;;
          esac
          curl -fsSL http://192.168.0.220:7655/download/pulse-agent?arch=linux-$ARCH \
            -o /agent-bin/pulse-agent
          chmod +x /agent-bin/pulse-agent
        volumeMounts:
        - name: agent-bin
          mountPath: /agent-bin
      containers:
      - name: pulse-agent
        image: alpine:3.20
        command:
        - /agent-bin/pulse-agent
        args:
        - --url
        - "http://192.168.0.220:7655"
        - --token
        - "$(PULSE_TOKEN)"
        - --enable-kubernetes
        env:
        - name: PULSE_TOKEN
          valueFrom:
            secretKeyRef:
              name: pulse-agent-token
              key: token
        volumeMounts:
        - name: agent-bin
          mountPath: /agent-bin
          readOnly: true
      volumes:
      - name: agent-bin
        emptyDir: {}
```

## Verification Steps

### 1. Check Agent Status

```bash
# If installed on node
ssh <node> systemctl status pulse-agent

# If running as pod
kubectl get pods -n pulse-agent
kubectl logs -n pulse-agent -l app=pulse-agent
```

### 2. Check Kubernetes Detection

The agent detects Kubernetes if:
- `kubectl` command is available, OR
- `/var/run/secrets/kubernetes.io/serviceaccount/token` exists (running in pod), OR
- `KUBECONFIG` environment variable is set, OR
- `~/.kube/config` file exists

### 3. Check Agent Logs

```bash
# Node installation
ssh <node> journalctl -u pulse-agent -f

# Pod installation
kubectl logs -n pulse-agent -l app=pulse-agent -f
```

Look for:
- `"Kubernetes agent module started"` - Success
- `"Kubernetes not available"` - Detection failed
- `"Failed to collect Kubernetes report"` - API access issue

### 4. Test Kubernetes API Access

```bash
# From agent pod/node
kubectl get nodes
kubectl get pods --all-namespaces
```

If these fail, the agent won't be able to monitor Kubernetes.

### 5. Check Pulse UI

1. Go to `http://192.168.0.220:7655`
2. Check **Dashboard** - Kubernetes cluster should appear
3. Check **Settings → Agents** - Agent should show as connected

## Common Issues

### Issue: "ImagePullBackOff" Error

**Cause**: Trying to use non-existent `rcourtman/pulse-agent:latest` image

**Solution**: 
- Use the init container approach (downloads binary)
- Or install directly on node (recommended)

### Issue: "Kubernetes not available" in logs

**Cause**: Agent can't access Kubernetes API

**Solutions**:
1. **If running in pod**: Ensure ServiceAccount has proper RBAC permissions
2. **If on node**: Ensure `kubectl` works or kubeconfig is accessible
3. **Check permissions**: Agent needs `get`, `list`, `watch` on nodes, pods, services, etc.

### Issue: Agent connects but no Kubernetes data

**Cause**: Kubernetes detection disabled or failed

**Solutions**:
1. **Force enable**: `--enable-kubernetes` flag
2. **Check detection**: Look for "Kubernetes agent module started" in logs
3. **Verify API access**: Test `kubectl` commands from agent location

### Issue: RBAC Permission Errors

**Cause**: ServiceAccount doesn't have required permissions

**Solution**: Ensure ClusterRole and ClusterRoleBinding are created:

```bash
kubectl get clusterrole pulse-agent
kubectl get clusterrolebinding pulse-agent
```

If missing, recreate them (see `install-kubernetes-agent.sh`).

## Node Selection

### Does the Agent Need to Run on a Control-Plane Node?

**No!** The Pulse agent can run on **any node** in your Kubernetes cluster, whether it's a control-plane node or a worker node.

**How It Works:**
- The agent connects to the Kubernetes API server (same endpoint from any node)
- It queries cluster resources (nodes, pods, deployments)
- It doesn't need special control-plane privileges
- One agent can monitor the entire cluster from any node

**Recommendation:**
- Use a worker node (less critical, more resources)
- One agent is sufficient to monitor the entire cluster
- Multiple agents provide redundancy

### K3s Worker Node Setup

For K3s worker nodes, you need to:
1. Install `kubectl` on the node
2. Copy kubeconfig from control-plane node to `/root/.kube/config`
3. Update server address in kubeconfig (change `127.0.0.1` to control-plane IP)
4. Grant RBAC permissions (see RBAC section below)

## RBAC Permissions

### Issue: Only Seeing Default Namespace

If the agent only shows pods/resources from the `default` namespace, the kubeconfig user needs ClusterRole permissions.

**Solution:**
```bash
kubectl create clusterrolebinding pulse-agent-default-user \
  --clusterrole=pulse-agent \
  --user=default
```

Replace `default` with the actual user from your kubeconfig context.

**Verify:**
```bash
kubectl auth can-i list pods --all-namespaces --as=system:user:default
```

## Quick Fix: Reinstall on Node

The simplest and most reliable method:

```bash
# 1. Get API token from Pulse UI
# 2. SSH to any Kubernetes node
ssh <node-name>

# 3. Install agent
curl -fsSL http://192.168.0.220:7655/install.sh | \
  sudo bash -s -- \
    --url http://192.168.0.220:7655 \
    --token <YOUR-TOKEN> \
    --enable-kubernetes

# 4. Verify
systemctl status pulse-agent
journalctl -u pulse-agent -f
```

## Why Node Installation is Better

1. **Direct API Access**: No RBAC complexity
2. **Auto-Detection**: Automatically detects Kubernetes
3. **Simpler**: No container orchestration needed
4. **Reliable**: One agent can monitor entire cluster
5. **Persistent**: Survives pod restarts

## Next Steps

After successful installation:

1. **Wait 1-2 minutes** for first report
2. **Check Pulse Dashboard** - Cluster should appear
3. **Verify metrics** - Nodes, pods, deployments should be visible
4. **Set up alerts** - Configure alerts for cluster issues

## Still Having Issues?

1. **Check agent logs** for specific errors
2. **Verify token** is correct and has proper scopes
3. **Test connectivity** from agent to Pulse server
4. **Check network** - Ensure agent can reach Pulse at `192.168.0.220:7655`
5. **Review documentation** - See `KUBERNETES_AGENT_SETUP.md` for detailed guide

