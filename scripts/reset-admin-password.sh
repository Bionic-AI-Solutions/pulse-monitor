#!/usr/bin/env bash
set -euo pipefail

# Reset Pulse Admin Password
# This script helps reset the admin password for Pulse running in Kubernetes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
KUBERNETES_NAMESPACE="${KUBERNETES_NAMESPACE:-pulse}"
POD_NAME="${POD_NAME:-}"
NEW_PASSWORD="${NEW_PASSWORD:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found"
    exit 1
fi

# Get pod name if not provided
if [ -z "$POD_NAME" ]; then
    POD_NAME=$(kubectl get pods -n "$KUBERNETES_NAMESPACE" -l app.kubernetes.io/name=pulse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$POD_NAME" ]; then
        log_error "No Pulse pod found in namespace $KUBERNETES_NAMESPACE"
        exit 1
    fi
fi

log_info "Using pod: $POD_NAME"

# Get new password
if [ -z "$NEW_PASSWORD" ]; then
    read -sp "Enter new admin password (min 12 characters): " NEW_PASSWORD
    echo
    if [ ${#NEW_PASSWORD} -lt 12 ]; then
        log_error "Password must be at least 12 characters long"
        exit 1
    fi
    
    read -sp "Confirm new password: " CONFIRM_PASSWORD
    echo
    if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
        log_error "Passwords do not match"
        exit 1
    fi
fi

log_info "Preparing password update..."

# Pulse will automatically hash plain text passwords on startup
# So we can set the plain text password and it will be hashed automatically
HASH="$NEW_PASSWORD"

log_info "Will set plain text password (Pulse will auto-hash on restart)"

# Read current .env file
log_info "Reading current .env file..."
ENV_CONTENT=$(kubectl exec -n "$KUBERNETES_NAMESPACE" "$POD_NAME" -- cat /data/.env 2>/dev/null || echo "")

if [ -z "$ENV_CONTENT" ]; then
    log_warn ".env file not found, creating new one..."
    ENV_CONTENT="# Pulse Configuration
PULSE_AUTH_USER='admin'
PULSE_AUTH_PASS='${HASH}'
"
else
    # Update password in .env content
    log_info "Updating password in .env file..."
    
    # Use awk to update or add PULSE_AUTH_PASS line
    ENV_CONTENT=$(echo "$ENV_CONTENT" | awk -v newpass="$HASH" '
        /^PULSE_AUTH_PASS=/ {
            print "PULSE_AUTH_PASS='"'"'" newpass "'"'"'"
            next
        }
        {
            print
        }
        END {
            if (!found) {
                print "PULSE_AUTH_PASS='"'"'" newpass "'"'"'"
            }
        }
    ')
fi

# Write updated .env file
log_info "Writing updated .env file to pod..."
echo "$ENV_CONTENT" | kubectl exec -i -n "$KUBERNETES_NAMESPACE" "$POD_NAME" -- sh -c 'cat > /data/.env && chmod 600 /data/.env'

if [ $? -eq 0 ]; then
    log_success ".env file updated"
else
    log_error "Failed to update .env file"
    exit 1
fi

# Restart the pod to apply changes
log_info "Restarting pod to apply password change..."
kubectl delete pod -n "$KUBERNETES_NAMESPACE" "$POD_NAME"

log_info "Waiting for pod to restart..."
sleep 5

# Wait for new pod to be ready
NEW_POD_NAME=$(kubectl get pods -n "$KUBERNETES_NAMESPACE" -l app.kubernetes.io/name=pulse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NEW_POD_NAME" ]; then
    log_info "Waiting for pod $NEW_POD_NAME to be ready..."
    kubectl wait --for=condition=ready pod/"$NEW_POD_NAME" -n "$KUBERNETES_NAMESPACE" --timeout=60s || true
fi

echo
log_success "=========================================="
log_success "Password reset complete!"
log_success "=========================================="
echo
log_info "You can now log in with:"
log_info "  Username: admin"
log_info "  Password: <the password you just set>"
echo
log_info "Note: If you used plain text, the password will be automatically hashed on next restart."

