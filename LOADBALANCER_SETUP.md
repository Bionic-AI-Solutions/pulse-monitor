# LoadBalancer Configuration

## Overview

Pulse is now configured to use a **LoadBalancer** service type, which provides an external IP address for accessing Pulse from outside the Kubernetes cluster.

## Current Configuration

The Helm chart has been updated to use `LoadBalancer` by default in `values.yaml`:

```yaml
service:
  type: LoadBalancer
  port: 7655
  annotations: {}
  loadBalancerIP: ""  # Optional: specify a static IP
  externalTrafficPolicy: Cluster
```

## Accessing Pulse

### Check LoadBalancer Status

```bash
kubectl get svc -n pulse
```

Example output:
```
NAME    TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)          AGE
pulse   LoadBalancer   10.43.25.235   192.168.0.220   7655:32261/TCP   8m30s
```

### Access Pulse

Once the LoadBalancer has an external IP assigned, access Pulse at:

```
http://<EXTERNAL-IP>:7655
```

For example:
```
http://192.168.0.220:7655
```

## Configuration Options

### Static IP Address

If you want to use a specific IP address for the LoadBalancer:

```yaml
service:
  type: LoadBalancer
  loadBalancerIP: "192.168.0.100"  # Your desired IP
```

Then deploy:
```bash
helm upgrade pulse ./deploy/helm/pulse -n pulse \
  --set service.loadBalancerIP=192.168.0.100
```

### Service Annotations

Some cloud providers require annotations for LoadBalancer configuration:

**For AWS (ELB):**
```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

**For GCP:**
```yaml
service:
  type: LoadBalancer
  annotations:
    cloud.google.com/load-balancer-type: "Internal"
```

**For Azure:**
```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

### External Traffic Policy

Control how traffic is routed:

- `Cluster` (default): Traffic can be routed to any node, then forwarded to the pod
- `Local`: Traffic is only routed to nodes that have a pod running

```yaml
service:
  type: LoadBalancer
  externalTrafficPolicy: Local  # Preserves source IP
```

## Deployment with LoadBalancer

### Using the Deployment Script

The deployment script now supports setting the service type:

```bash
export SERVICE_TYPE="LoadBalancer"
export DOCKER_USERNAME="your-username"
export DOCKER_PASSWORD="your-password"
export CREATE_REGISTRY_SECRET="true"

./scripts/build-and-deploy.sh
```

### Manual Helm Deployment

```bash
helm upgrade --install pulse ./deploy/helm/pulse -n pulse \
  --set service.type=LoadBalancer \
  --set imagePullSecrets[0].name=docker-registry-secret
```

## Troubleshooting

### LoadBalancer IP is "Pending"

If the external IP shows as `<pending>`, it may be:

1. **Cloud Provider**: Your cluster may not support LoadBalancer (e.g., bare metal)
   - **Solution**: Use NodePort or Ingress instead

2. **LoadBalancer Controller**: The cluster may not have a LoadBalancer controller
   - **Solution**: Install MetalLB (for bare metal) or use cloud provider's controller

3. **IP Pool Exhausted**: No available IPs in the LoadBalancer pool
   - **Solution**: Check LoadBalancer controller logs

### Check LoadBalancer Events

```bash
kubectl describe svc pulse -n pulse
```

Look for events that indicate why the IP is pending.

### Alternative: Use NodePort

If LoadBalancer isn't available, use NodePort:

```yaml
service:
  type: NodePort
  port: 7655
```

Then access via: `http://<NODE-IP>:<NODE-PORT>`

### Alternative: Use Ingress

For more control, use Ingress:

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: pulse.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: pulse-tls
      hosts:
        - pulse.example.com
```

## Verification

After deployment, verify the LoadBalancer:

```bash
# Check service
kubectl get svc pulse -n pulse

# Get external IP
kubectl get svc pulse -n pulse -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test connectivity
curl http://<EXTERNAL-IP>:7655/api/health
```

## Security Considerations

1. **Firewall Rules**: Ensure port 7655 is open in your firewall
2. **TLS/HTTPS**: Consider using Ingress with TLS instead of exposing HTTP directly
3. **Authentication**: Ensure Pulse authentication is properly configured
4. **Network Policies**: Consider restricting access with Kubernetes NetworkPolicies

## Reverting to ClusterIP

If you want to revert to ClusterIP (internal only):

```bash
helm upgrade pulse ./deploy/helm/pulse -n pulse \
  --set service.type=ClusterIP
```

Or update `values.yaml`:
```yaml
service:
  type: ClusterIP
```

Then redeploy.

