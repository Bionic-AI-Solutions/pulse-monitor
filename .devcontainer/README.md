# Pulse Development Container

This devcontainer provides a complete development environment for the Pulse project with Docker and kubectl pre-configured.

## Features

- **Go 1.24** development environment
- **Docker** pre-installed (uses host Docker daemon when available)
- **kubectl** configured to use host binary and config
- **VS Code extensions** pre-installed for Go and Kubernetes development

## Prerequisites

- VS Code with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- Docker Desktop or Docker Engine running on your host machine
- (Optional) kubectl installed on your host machine
- (Optional) `~/.kube/config` file on your host machine

## Setup

1. Open the project in VS Code
2. When prompted, click "Reopen in Container" or use the Command Palette:
   - Press `F1` or `Ctrl+Shift+P` (Mac: `Cmd+Shift+P`)
   - Select "Dev Containers: Reopen in Container"

The container will build automatically and set up the development environment.

## Docker Configuration

The devcontainer uses the host Docker daemon by mounting `/var/run/docker.sock`. This means:
- Containers you build/run inside the devcontainer will run on your host Docker
- You can access all Docker images and containers from your host
- No need for Docker-in-Docker (though it's available as a fallback)

## kubectl Configuration

The devcontainer includes kubectl pre-installed in the container.

### Using Host kubeconfig (Optional)

To use your host's kubeconfig file, you can mount it by adding this mount to the `mounts` array in `.devcontainer/devcontainer.json`:

```json
"source=${localEnv:HOME}/.kube,target=/home/vscode/.kube-host,type=bind,consistency=cached"
```

**Important**: Ensure the `~/.kube` directory exists on your host before adding this mount, otherwise the container will fail to start.

After adding the mount and rebuilding the container, your kubeconfig will be:
- Mounted at `/home/vscode/.kube-host/config`
- Symlinked to `/home/vscode/.kube/config` for convenience
- `KUBECONFIG` environment variable is set automatically

### Verifying kubectl Setup

After the container starts, verify kubectl is working:

```bash
kubectl version --client
kubectl cluster-info
kubectl get nodes
```

## Port Forwarding

The following ports are forwarded from the container to your host:
- **7655**: Pulse server (auto-forwarded with notification)

## Development Workflow

1. **Build the project**:
   ```bash
   make build
   # or
   go build ./cmd/pulse
   ```

2. **Run tests**:
   ```bash
   go test ./...
   ```

3. **Run the application**:
   ```bash
   ./pulse
   ```

4. **Use Docker**:
   ```bash
   docker ps
   docker build -t pulse:dev .
   ```

5. **Use kubectl**:
   ```bash
   kubectl get pods
   kubectl apply -f deploy/helm/pulse/
   ```

## Troubleshooting

### Docker not working

If Docker commands fail:
1. Ensure Docker Desktop/Engine is running on your host
2. Check that `/var/run/docker.sock` exists on your host
3. The container will fall back to Docker-in-Docker if the host socket isn't available

### kubectl not found

If kubectl is not available:
1. Install kubectl on your host machine
2. Or the container will use its own kubectl installation (may need cluster access configuration)

### kubeconfig not working

If kubectl can't connect to your cluster:
1. Verify `~/.kube/config` exists on your host
2. Check file permissions (should be readable)
3. Ensure the kubeconfig file has valid cluster credentials

### Permission issues

If you encounter permission issues:
- The container runs as the `vscode` user (UID 1000)
- Docker commands may require sudo (handled automatically via Docker group)
- File permissions are automatically adjusted

## Customization

You can customize the devcontainer by editing:
- `.devcontainer/devcontainer.json` - Container configuration
- `.devcontainer/Dockerfile` - Container image definition
- `.devcontainer/post-create.sh` - Post-creation setup script

## VS Code Extensions

The following extensions are automatically installed:
- Go (golang.go)
- Kubernetes (ms-kubernetes-tools.vscode-kubernetes-tools)
- Docker (ms-azuretools.vscode-docker)
- YAML (redhat.vscode-yaml)
- GitLens (eamodio.gitlens)


