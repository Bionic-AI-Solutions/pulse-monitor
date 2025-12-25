# Reset Admin Password Guide

This guide explains how to reset the admin password for Pulse, especially when running in Kubernetes.

## Quick Reset (Kubernetes)

Use the provided script:

```bash
./scripts/reset-admin-password.sh
```

The script will:
1. Prompt for a new password
2. Generate a bcrypt hash
3. Update the `.env` file in the pod
4. Restart the pod to apply changes

## Manual Reset Methods

### Method 1: Using the Reset Script (Recommended)

```bash
# Interactive mode
./scripts/reset-admin-password.sh

# Or with environment variables
export NEW_PASSWORD="your-new-password-here"
export KUBERNETES_NAMESPACE="pulse"
./scripts/reset-admin-password.sh
```

### Method 2: Direct Pod Access

1. **Get the pod name:**
   ```bash
   kubectl get pods -n pulse
   ```

2. **Generate password hash:**
   ```bash
   # Option A: Use the hashpw utility in the pod
   kubectl exec -n pulse <pod-name> -- /app/pulse hashpw "your-new-password"
   
   # Option B: Use plain text (will be auto-hashed on restart)
   # Pulse will automatically hash plain text passwords on startup
   ```

3. **Edit the .env file:**
   ```bash
   # Get current .env
   kubectl exec -n pulse <pod-name> -- cat /data/.env
   
   # Update password (replace the hash)
   kubectl exec -n pulse <pod-name> -- sh -c "sed -i \"s/PULSE_AUTH_PASS=.*/PULSE_AUTH_PASS='\$2a\$12\$...your-hash-here...'/'\" /data/.env"
   
   # Or set plain text (will be auto-hashed)
   kubectl exec -n pulse <pod-name> -- sh -c "sed -i \"s/PULSE_AUTH_PASS=.*/PULSE_AUTH_PASS='your-new-password'/'\" /data/.env"
   ```

4. **Restart the pod:**
   ```bash
   kubectl delete pod -n pulse <pod-name>
   ```

### Method 3: Using Environment Variables (Temporary)

You can set the password via environment variable, but this is **temporary** and will be lost on pod restart:

```bash
# Update Helm values
helm upgrade pulse ./deploy/helm/pulse -n pulse \
  --set server.extraEnv[0].name=PULSE_AUTH_PASS \
  --set server.extraEnv[0].value="your-new-password"
```

**Note**: This is temporary. For permanent change, use Method 1 or 2.

### Method 4: Edit PVC Directly (Advanced)

If you have direct access to the storage:

1. **Find the PVC:**
   ```bash
   kubectl get pvc -n pulse
   ```

2. **Mount the PVC on a temporary pod:**
   ```bash
   kubectl run -it --rm debug --image=busybox --restart=Never -n pulse -- \
     sh -c "mount /path/to/pvc /mnt && vi /mnt/.env"
   ```

3. **Edit the `.env` file** and update `PULSE_AUTH_PASS`

4. **Restart the Pulse pod**

## Password Requirements

- **Minimum length**: 12 characters
- **Format**: Can be any characters (no complexity requirements)
- **Storage**: Stored as bcrypt hash (60 characters, starts with `$2a$`)

## Password Hash Format

Pulse uses bcrypt with cost factor 12. The hash format is:
```
$2a$12$<salt><hash>
```

Example:
```
$2a$12$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy
```

## Generating Password Hashes

### Using Pulse's hashpw utility:

```bash
# In the pod
kubectl exec -n pulse <pod-name> -- /app/pulse hashpw "your-password"
```

### Using Go (if available):

```bash
go run - << 'EOF'
package main
import (
    "fmt"
    "golang.org/x/crypto/bcrypt"
)
func main() {
    hash, _ := bcrypt.GenerateFromPassword([]byte("your-password"), 12)
    fmt.Println(string(hash))
}
EOF
```

### Using online tools (not recommended for production):

You can use bcrypt generators, but **be cautious** with security.

## Verification

After resetting the password:

1. **Wait for pod to restart:**
   ```bash
   kubectl get pods -n pulse
   ```

2. **Check logs for errors:**
   ```bash
   kubectl logs -n pulse -l app.kubernetes.io/name=pulse --tail=50
   ```

3. **Test login:**
   ```bash
   # Access via LoadBalancer
   curl -u admin:your-new-password http://<EXTERNAL-IP>:7655/api/health
   
   # Or via port-forward
   kubectl port-forward -n pulse svc/pulse 7655:7655
   # Then open http://localhost:7655
   ```

## Troubleshooting

### Password not working after reset

1. **Check .env file:**
   ```bash
   kubectl exec -n pulse <pod-name> -- cat /data/.env
   ```

2. **Verify hash format:**
   - Should be 60 characters
   - Should start with `$2a$`, `$2b$`, or `$2y$`

3. **Check if pod restarted:**
   ```bash
   kubectl get pods -n pulse
   kubectl describe pod -n pulse <pod-name>
   ```

4. **Check application logs:**
   ```bash
   kubectl logs -n pulse <pod-name> | grep -i password
   ```

### Plain text password not being hashed

If you set a plain text password and it's not being hashed:

1. **Check if .env file is writable:**
   ```bash
   kubectl exec -n pulse <pod-name> -- ls -la /data/.env
   ```

2. **Check application logs** for hashing errors

3. **Manually generate hash** and update .env file

### Cannot access pod

If you can't exec into the pod:

1. **Check pod status:**
   ```bash
   kubectl get pods -n pulse
   kubectl describe pod -n pulse <pod-name>
   ```

2. **Use a debug pod** to access the PVC:
   ```bash
   kubectl run -it --rm debug --image=busybox --restart=Never -n pulse -- sh
   # Then mount the PVC volume
   ```

## Security Considerations

1. **Never commit passwords** to version control
2. **Use strong passwords** (even though there's no complexity requirement, use a strong password)
3. **Rotate passwords regularly**
4. **Use environment variables** only for temporary testing
5. **Restrict access** to the `.env` file (should be 600 permissions)

## Alternative: Change Password via UI

If you can still log in with the current password:

1. Log in to Pulse UI
2. Go to **Settings → Security**
3. Click **Change Password**
4. Enter current and new password
5. The password will be updated automatically

**Note**: This requires knowing the current password.

## File Locations

- **Kubernetes/Docker**: `/data/.env`
- **Systemd**: `/etc/pulse/.env`

The `.env` file format:
```bash
PULSE_AUTH_USER='admin'
PULSE_AUTH_PASS='$2a$12$...bcrypt-hash...'
```

## Related Documentation

- [Configuration Guide](docs/CONFIGURATION.md)
- [Security Guide](SECURITY.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

