# Pulse Deployment Guide

This guide covers building, pushing, and deploying Pulse to Kubernetes.

## Prerequisites

1. **Docker** - Installed and running
2. **kubectl** - Configured to access your Kubernetes cluster
3. **Helm** - Version 3.x installed
4. **Docker Registry Access** - Credentials for pushing images (Docker Hub, GHCR, etc.)

## Quick Start

### 1. Set Environment Variables

```bash
# Required: Docker registry credentials
export DOCKER_USERNAME="your-username"
export DOCKER_PASSWORD="your-password"  # Or use 'docker login' manually

# Optional: Customize deployment
export DOCKER_REGISTRY="docker.io"              # or "ghcr.io" for GitHub Container Registry
export DOCKER_NAMESPACE="your-org"              # Docker Hub org or GHCR namespace
export KUBERNETES_NAMESPACE="pulse"             # Kubernetes namespace (default: pulse)
export HELM_RELEASE_NAME="pulse"                 # Helm release name
```

### 2. Run the Deployment Script

```bash
# Full build, push, and deploy
./scripts/build-and-deploy.sh
```

The script will:
1. Read the version from `VERSION` file
2. Build the Docker image
3. Push to your Docker registry
4. Deploy to Kubernetes using Helm

## Step-by-Step Deployment

### Option 1: All-in-One Script

The `build-and-deploy.sh` script handles everything:

```bash
# Full deployment
DOCKER_USERNAME=myuser DOCKER_PASSWORD=mypass ./scripts/build-and-deploy.sh
```

### Option 2: Manual Steps

#### Step 1: Build Docker Image

```bash
# Get version
VERSION=$(cat VERSION)

# Build image
docker build \
  --platform linux/amd64 \
  --target runtime \
  --tag your-registry/your-org/pulse:${VERSION} \
  --tag your-registry/your-org/pulse:latest \
  -f Dockerfile .
```

#### Step 2: Push to Registry

```bash
# Login to registry (if not already logged in)
docker login your-registry

# Push image
docker push your-registry/your-org/pulse:${VERSION}
docker push your-registry/your-org/pulse:latest
```

#### Step 3: Deploy to Kubernetes

```bash
# Create namespace (if needed)
kubectl create namespace pulse

# Deploy with Helm
helm upgrade --install pulse ./deploy/helm/pulse \
  --namespace pulse \
  --set image.repository=your-registry/your-org/pulse \
  --set image.tag=${VERSION} \
  --wait \
  --timeout 10m
```

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_REGISTRY` | `docker.io` | Docker registry URL |
| `DOCKER_USERNAME` | - | Registry username |
| `DOCKER_PASSWORD` | - | Registry password |
| `DOCKER_IMAGE` | `pulse` | Image name |
| `DOCKER_NAMESPACE` | `rcourtman` | Registry namespace/org |
| `KUBERNETES_NAMESPACE` | `pulse` | K8s namespace |
| `HELM_RELEASE_NAME` | `pulse` | Helm release name |
| `HELM_CHART_PATH` | `./deploy/helm/pulse` | Path to Helm chart |
| `BUILD_PLATFORM` | `linux/amd64` | Build platform |
| `SKIP_BUILD` | `false` | Skip build step |
| `SKIP_PUSH` | `false` | Skip push step |
| `SKIP_DEPLOY` | `false` | Skip deploy step |

### Build Options

```bash
# Build for multiple platforms (requires buildx)
BUILD_PLATFORM="linux/amd64,linux/arm64" ./scripts/build-and-deploy.sh

# Skip agent binaries (faster build)
BUILD_AGENT=0 docker build ...
```

### Deployment Options

#### Custom Helm Values

Create a `values.yaml` file:

```yaml
image:
  repository: your-registry/your-org/pulse
  tag: "5.0.3"
  pullPolicy: Always

persistence:
  enabled: true
  size: 20Gi
  storageClass: fast-ssd

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

Then deploy:

```bash
helm upgrade --install pulse ./deploy/helm/pulse \
  --namespace pulse \
  -f values.yaml
```

## Examples

### Docker Hub

```bash
export DOCKER_USERNAME="myuser"
export DOCKER_PASSWORD="mypassword"
export DOCKER_NAMESPACE="myuser"
./scripts/build-and-deploy.sh
```

### GitHub Container Registry (GHCR)

```bash
export DOCKER_REGISTRY="ghcr.io"
export DOCKER_USERNAME="your-github-username"
export DOCKER_PASSWORD="${GITHUB_TOKEN}"  # GitHub Personal Access Token
export DOCKER_NAMESPACE="your-github-username"
./scripts/build-and-deploy.sh
```

### Private Registry

```bash
export DOCKER_REGISTRY="registry.example.com"
export DOCKER_USERNAME="registry-user"
export DOCKER_PASSWORD="registry-pass"
export DOCKER_NAMESPACE="myorg"
./scripts/build-and-deploy.sh
```

### Build Only (No Push/Deploy)

```bash
SKIP_PUSH=true SKIP_DEPLOY=true ./scripts/build-and-deploy.sh
```

### Push Only (Skip Build)

```bash
SKIP_BUILD=true DOCKER_USERNAME=myuser ./scripts/build-and-deploy.sh
```

### Deploy Only (Skip Build/Push)

```bash
SKIP_BUILD=true SKIP_PUSH=true ./scripts/build-and-deploy.sh
```

## Verifying Deployment

### Check Pod Status

```bash
kubectl get pods -n pulse -l app.kubernetes.io/name=pulse
```

### Check Service

```bash
kubectl get svc -n pulse
```

### View Logs

```bash
kubectl logs -n pulse -l app.kubernetes.io/name=pulse --tail=100 -f
```

### Access the UI

```bash
# Port forward to access locally
kubectl port-forward -n pulse svc/pulse 7655:7655

# Then access at http://localhost:7655
```

## Troubleshooting

### Build Issues

**Issue**: Build fails with "go: cannot find module"
- **Solution**: Ensure `go.mod` and `go.sum` are up to date

**Issue**: Frontend build fails
- **Solution**: Check Node.js version (requires Node 20+)

### Push Issues

**Issue**: Authentication failed
- **Solution**: Run `docker login` manually or set `DOCKER_PASSWORD`

**Issue**: Permission denied
- **Solution**: Ensure you have push permissions to the registry

### Deployment Issues

**Issue**: Helm install fails
- **Solution**: Check `kubectl` access and namespace exists

**Issue**: Pods not starting
- **Solution**: Check logs with `kubectl logs -n pulse <pod-name>`

**Issue**: Image pull errors
- **Solution**: Verify image exists in registry and check imagePullSecrets

## Updating Deployment

### Update to New Version

1. Update `VERSION` file with new version
2. Run deployment script:

```bash
./scripts/build-and-deploy.sh
```

Helm will automatically upgrade the release.

### Rollback

```bash
# List releases
helm list -n pulse

# Rollback to previous version
helm rollback pulse -n pulse

# Rollback to specific revision
helm rollback pulse 2 -n pulse
```

## Advanced Configuration

### Persistent Storage

Pulse requires persistent storage for configuration and metrics. The Helm chart creates a PVC by default. To use an existing PVC:

```yaml
persistence:
  enabled: true
  existingClaim: "pulse-data"
```

### Resource Limits

```yaml
server:
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
```

### Environment Variables

```yaml
server:
  env:
    - name: TZ
      value: "America/New_York"
    - name: PULSE_LOG_LEVEL
      value: "info"
  extraEnv:
    - name: CUSTOM_VAR
      value: "custom-value"
```

### Ingress Configuration

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
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

## Security Considerations

1. **Image Pull Secrets**: Use imagePullSecrets for private registries
2. **TLS**: Enable TLS for ingress
3. **RBAC**: Review ServiceAccount permissions
4. **Secrets**: Store sensitive data in Kubernetes Secrets
5. **Network Policies**: Consider implementing network policies

## Next Steps

After deployment:

1. **Access the UI**: Set up ingress or port-forward
2. **Configure Nodes**: Add Proxmox nodes via the web UI
3. **Set Up Alerts**: Configure notification channels
4. **Install Agents**: Install agents on Docker hosts/K8s clusters
5. **Review Documentation**: See `docs/` for detailed guides

## Support

- **Documentation**: See `docs/README.md`
- **Issues**: https://github.com/rcourtman/Pulse/issues
- **Discussions**: https://github.com/rcourtman/Pulse/discussions

