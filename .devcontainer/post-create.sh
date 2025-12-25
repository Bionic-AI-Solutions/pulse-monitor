#!/bin/bash
set -e

echo "🚀 Setting up Pulse development environment..."

# Set up kubeconfig from host mount (if available)
if [ -d /home/vscode/.kube-host ] && [ -f /home/vscode/.kube-host/config ]; then
    mkdir -p /home/vscode/.kube
    if [ ! -f /home/vscode/.kube/config ] || [ ! -L /home/vscode/.kube/config ]; then
        ln -sf /home/vscode/.kube-host/config /home/vscode/.kube/config
        echo "✅ Linked kubeconfig from host mount"
    fi
    export KUBECONFIG=/home/vscode/.kube-host/config
    echo "export KUBECONFIG=/home/vscode/.kube-host/config" >> /home/vscode/.bashrc
    echo "✅ Set KUBECONFIG environment variable"
else
    echo "ℹ️  Host kubeconfig not mounted"
    echo "   To use your host kubeconfig:"
    echo "   1. Ensure ~/.kube directory exists on your host"
    echo "   2. Uncomment the kubeconfig mount in .devcontainer/devcontainer.json"
    echo "   3. Rebuild the container"
    mkdir -p /home/vscode/.kube
fi

# Set up Docker to use host socket
if [ -S /var/run/docker-host.sock ]; then
    # Create symlink to host docker socket
    sudo ln -sf /var/run/docker-host.sock /var/run/docker.sock 2>/dev/null || true
    echo "✅ Linked Docker socket from host"
    
    # Test Docker connection
    if docker info > /dev/null 2>&1; then
        echo "✅ Docker is working correctly"
        docker version
    else
        echo "⚠️  Docker socket found but connection failed"
    fi
else
    echo "⚠️  Host Docker socket not found at /var/run/docker-host.sock"
    echo "   Docker-in-Docker will be used instead"
fi

# Verify kubectl
if command -v kubectl > /dev/null 2>&1; then
    echo ""
    echo "📋 kubectl information:"
    kubectl version --client 2>/dev/null || echo "   kubectl found but version check failed"
    
    if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
        echo "   Using kubeconfig: $KUBECONFIG"
        if kubectl cluster-info > /dev/null 2>&1; then
            echo "✅ kubectl can connect to cluster"
            kubectl cluster-info | head -1
        else
            echo "⚠️  kubectl configured but cannot connect to cluster"
        fi
    fi
fi

# Install Go dependencies if go.mod exists
if [ -f /workspace/go.mod ]; then
    echo ""
    echo "📦 Installing Go dependencies..."
    cd /workspace
    go mod download
    echo "✅ Go dependencies installed"
fi

echo ""
echo "✨ Development environment setup complete!"
echo ""
echo "Available tools:"
echo "  - Go: $(go version | cut -d' ' -f3)"
echo "  - Docker: $(docker --version 2>/dev/null || echo 'Not available')"
echo "  - kubectl: $(kubectl version --client --short 2>/dev/null | head -1 || echo 'Not available')"
echo ""


