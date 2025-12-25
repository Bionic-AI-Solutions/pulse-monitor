# Deployment Troubleshooting Guide

## Issue: ImagePullBackOff Error

### Symptom
```
Events:
  Warning  Failed  Failed to pull image "docker.io/docker4zerocool/pulse:5.0.3": 
  pull access denied, repository does not exist or may require authorization: 
  server message: insufficient_scope: authorization failed
```

### Root Cause
Kubernetes cannot pull the Docker image because:
1. The image is in a private repository, OR
2. The repository requires authentication, OR
3. The cluster doesn't have credentials to access the registry

### Solution

#### Option 1: Quick Fix (Recommended)
Use the fix script to create the registry secret and update the deployment:

```bash
# Set your Docker credentials
export DOCKER_USERNAME="docker4zerocool"
export DOCKER_PASSWORD="your-password"

# Run the fix script
./scripts/fix-deployment.sh
```

#### Option 2: Manual Fix

1. **Create Registry Secret**:
```bash
kubectl create secret docker-registry docker-registry-secret \
  --docker-server=docker.io \
  --docker-username=your-username \
  --docker-password=your-password \
  --namespace=pulse
```

2. **Update Deployment**:
```bash
kubectl patch deployment pulse -n pulse -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"docker-registry-secret"}]}}}}'
```

3. **Wait for Rollout**:
```bash
kubectl rollout status deployment/pulse -n pulse
```

#### Option 3: Redeploy with Secret

Use the updated deployment script with registry secret creation:

```bash
export DOCKER_USERNAME="docker4zerocool"
export DOCKER_PASSWORD="your-password"
export CREATE_REGISTRY_SECRET="true"

# Skip build and push, just deploy
SKIP_BUILD=true SKIP_PUSH=true ./scripts/build-and-deploy.sh
```

## Issue: Helm Timeout

### Symptom
```
Error: context deadline exceeded
```

### Root Cause
- Pods are taking too long to start
- Image pull issues (see above)
- Resource constraints
- Default timeout (10m) is too short

### Solution

1. **Increase Timeout**:
```bash
export HELM_TIMEOUT="20m"
./scripts/build-and-deploy.sh
```

2. **Check Pod Status**:
```bash
kubectl get pods -n pulse
kubectl describe pod <pod-name> -n pulse
```

3. **Check Events**:
```bash
kubectl get events -n pulse --sort-by='.lastTimestamp'
```

## Issue: Build Fails

### Common Causes

1. **Docker not running**:
```bash
docker ps  # Should work without errors
```

2. **Insufficient disk space**:
```bash
df -h  # Check available space
```

3. **Network issues**:
```bash
docker pull node:20-alpine  # Test Docker connectivity
```

### Solution
- Ensure Docker daemon is running
- Free up disk space
- Check network connectivity

## Issue: Push Fails

### Common Causes

1. **Authentication failed**:
```bash
docker login docker.io
```

2. **Permission denied**:
- Verify you have push permissions to the repository
- Check if the repository exists

3. **Network issues**:
- Check internet connectivity
- Verify registry is accessible

### Solution
```bash
# Test login
docker login docker.io

# Test push with a small image
docker tag hello-world docker.io/your-username/test:latest
docker push docker.io/your-username/test:latest
```

## Issue: Deployment Succeeds but Pods Crash

### Debugging Steps

1. **Check Pod Logs**:
```bash
kubectl logs -n pulse -l app.kubernetes.io/name=pulse --tail=100
```

2. **Check Pod Status**:
```bash
kubectl describe pod <pod-name> -n pulse
```

3. **Check Events**:
```bash
kubectl get events -n pulse --sort-by='.lastTimestamp'
```

4. **Check Resource Limits**:
```bash
kubectl top pod -n pulse
```

### Common Fixes

- **Out of Memory**: Increase memory limits in Helm values
- **Crash Loop**: Check application logs for errors
- **Config Issues**: Verify environment variables and config maps

## Verification Commands

### Check Deployment Status
```bash
# Helm release status
helm list -n pulse

# Pod status
kubectl get pods -n pulse -l app.kubernetes.io/name=pulse

# Service status
kubectl get svc -n pulse

# Deployment status
kubectl get deployment pulse -n pulse
```

### Check Logs
```bash
# Application logs
kubectl logs -n pulse -l app.kubernetes.io/name=pulse --tail=100 -f

# Previous container logs (if crashed)
kubectl logs -n pulse -l app.kubernetes.io/name=pulse --previous
```

### Access the Application
```bash
# Port forward
kubectl port-forward -n pulse svc/pulse 7655:7655

# Then access http://localhost:7655
```

## Prevention

### For Future Deployments

1. **Always create registry secret**:
```bash
export CREATE_REGISTRY_SECRET="true"
export DOCKER_USERNAME="your-username"
export DOCKER_PASSWORD="your-password"
./scripts/build-and-deploy.sh
```

2. **Use longer timeout for first deployment**:
```bash
export HELM_TIMEOUT="20m"
./scripts/build-and-deploy.sh
```

3. **Verify image exists before deploying**:
```bash
docker pull docker.io/your-username/pulse:5.0.3
```

## Getting Help

If issues persist:

1. **Collect Information**:
```bash
# Save these outputs
kubectl get all -n pulse > k8s-status.txt
kubectl describe pod <pod-name> -n pulse > pod-describe.txt
kubectl logs <pod-name> -n pulse > pod-logs.txt
```

2. **Check Documentation**:
- See `DEPLOYMENT_GUIDE.md` for detailed instructions
- See `DEPLOYMENT_SUMMARY.md` for quick reference

3. **Common Issues**:
- Image pull errors → Create registry secret
- Timeout errors → Increase timeout or check pod status
- Build errors → Check Docker and disk space
- Push errors → Verify credentials and permissions

