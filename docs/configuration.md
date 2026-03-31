# Configuration Guide

Complete guide for configuring OpenClaw deployment on OpenShift.

## Table of Contents

- [Configuration Overview](#configuration-overview)
- [ConfigMap Configuration](#configmap-configuration)
- [Secret Configuration](#secret-configuration)
- [Resource Configuration](#resource-configuration)
- [Storage Configuration](#storage-configuration)
- [Network Configuration](#network-configuration)
- [Security Configuration](#security-configuration)
- [Environment-Specific Configuration](#environment-specific-configuration)

---

## Configuration Overview

OpenClaw configuration is managed through multiple layers:

| Layer | Type | Purpose | Editability |
|-------|------|---------|-------------|
| **Base Manifests** | YAML | Foundation resources | Via Git |
| **Kustomize Overlays** | YAML patches | Environment-specific overrides | Via Git |
| **ConfigMap** | Key-value | Application configuration | Runtime via `oc` |
| **Secret** | Encoded key-value | Sensitive data (API keys) | Runtime via `oc` or script |

---

## ConfigMap Configuration

### Viewing Current Configuration

```bash
# View ConfigMap
oc get configmap -n openclaw -l app.kubernetes.io/name=openclaw

# View ConfigMap details
oc describe configmap openclaw-config -n openclaw

# Export ConfigMap to YAML
oc get configmap openclaw-config -n openclaw -o yaml
```

### Editing ConfigMap

#### Method 1: Edit Directly

```bash
# Edit interactively
oc edit configmap openclaw-config -n openclaw

# Restart deployment to apply changes
oc rollout restart deployment openclaw -n openclaw
```

#### Method 2: Patch ConfigMap

```bash
# Update specific key
oc patch configmap openclaw-config -n openclaw \
  --type merge \
  -p '{"data":{"LOG_LEVEL":"debug"}}'

# Restart deployment
oc rollout restart deployment openclaw -n openclaw
```

#### Method 3: Update and Apply Manifest

```bash
# Edit manifests/base/configmap.yaml
# Then apply
oc apply -f manifests/base/configmap.yaml

# Restart deployment
oc rollout restart deployment openclaw -n openclaw
```

### Available ConfigMap Options

| Key | Default | Description | Values |
|-----|---------|-------------|--------|
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway HTTP port | Any valid port number |
| `OPENCLAW_GATEWAY_BIND` | `0.0.0.0` | Gateway bind address | IP or `0.0.0.0` |
| `OPENCLAW_SANDBOX` | `1` | Enable sandbox mode for isolation | `0` (off), `1` (on) |
| `OPENCLAW_STATE_DIR` | `/data` | Persistent state directory | Any writable path |
| `LOG_LEVEL` | `info` | Logging verbosity | `debug`, `info`, `warn`, `error` |
| `HEALTHCHECK_ENABLED` | `true` | Enable health endpoints | `true`, `false` |
| `HEALTHCHECK_PATH` | `/healthz` | Health check endpoint path | Any path |
| `READINESS_PATH` | `/readyz` | Readiness check endpoint path | Any path |

### Example: Enable Debug Logging

```bash
# Update log level
oc patch configmap openclaw-config -n openclaw \
  --type merge \
  -p '{"data":{"LOG_LEVEL":"debug"}}'

# Restart to apply
oc rollout restart deployment openclaw -n openclaw

# Wait for rollout
oc rollout status deployment openclaw -n openclaw

# Verify logs
oc logs -f deployment/openclaw -n openclaw
```

---

## Secret Configuration

### Viewing Secrets (Safely)

```bash
# List secrets
oc get secret -n openclaw

# View secret keys (not values)
oc get secret openclaw-secrets -n openclaw -o jsonpath='{.data}' | jq 'keys'

# Decode specific secret value (be careful in shared terminals!)
oc get secret openclaw-secrets -n openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d
```

### Updating Secrets

#### Method 1: Using Script (Recommended)

```bash
# Run interactive wizard
./scripts/create-secrets.sh
```

This handles:
- Generating secure tokens
- Prompting for API keys
- Creating/updating secret
- Restarting deployment

#### Method 2: Manual Update

```bash
# Delete existing secret
oc delete secret openclaw-secrets -n openclaw

# Create new secret
oc create secret generic openclaw-secrets -n openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --from-literal=ANTHROPIC_API_KEY="sk-ant-your-key" \
  --from-literal=OPENAI_API_KEY="sk-your-key"

# Restart deployment
oc rollout restart deployment openclaw -n openclaw
```

#### Method 3: Patch Existing Secret

```bash
# Update single key
oc patch secret openclaw-secrets -n openclaw \
  --type merge \
  -p "{\"data\":{\"ANTHROPIC_API_KEY\":\"$(echo -n 'sk-ant-new-key' | base64)\"}}"

# Restart deployment
oc rollout restart deployment openclaw -n openclaw
```

### Required Secret Keys

| Key | Format | Required | Description |
|-----|--------|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | Hex string | ✅ Yes | Gateway authentication token |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | ⚠️ One required | Anthropic Claude API key |
| `OPENAI_API_KEY` | `sk-...` | ⚠️ One required | OpenAI GPT API key |
| `OPENROUTER_API_KEY` | `sk-or-...` | ❌ Optional | OpenRouter API key |
| `GOOGLE_API_KEY` | Various | ❌ Optional | Google AI API key |

**Note**: At least one AI provider API key must be configured.

---

## Resource Configuration

### Viewing Current Resources

```bash
# View deployment resource limits
oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq
```

### Updating Resource Limits

#### Via Kustomize Overlay (Recommended)

Edit `manifests/lab/kustomization.yaml` or `manifests/production/kustomization.yaml`:

```yaml
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: openclaw
    namespace: openclaw
  spec:
    template:
      spec:
        containers:
        - name: openclaw
          resources:
            requests:
              memory: "4Gi"
              cpu: "2000m"
            limits:
              memory: "16Gi"
              cpu: "8000m"
```

Then apply:

```bash
oc apply -k manifests/production
```

#### Via Direct Edit

```bash
# Edit deployment directly
oc edit deployment openclaw -n openclaw

# Find resources section and update values
# Deployment will automatically restart
```

### Recommended Resource Profiles

| Workload Type | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---------------|-------------|-----------|----------------|--------------|
| **Lab/Testing** | 500m | 2000m | 1Gi | 4Gi |
| **Light Production** | 1000m | 4000m | 2Gi | 8Gi |
| **Standard Production** | 2000m | 8000m | 4Gi | 16Gi |
| **Heavy Production** | 4000m | 16000m | 8Gi | 32Gi |

---

## Storage Configuration

### Viewing Storage

```bash
# View PVC
oc get pvc -n openclaw

# View PVC details
oc describe pvc openclaw-data -n openclaw

# Check storage usage (requires pod exec)
oc exec -n openclaw deployment/openclaw -- df -h /data
```

### Resizing PVC

#### Prerequisites

- StorageClass must support volume expansion (`allowVolumeExpansion: true`)

```bash
# Check if storage class allows expansion
oc get storageclass <your-storage-class> -o jsonpath='{.allowVolumeExpansion}'
# Should return: true
```

#### Resize Procedure

```bash
# 1. Edit PVC
oc edit pvc openclaw-data -n openclaw

# 2. Update spec.resources.requests.storage
# Change from: storage: 40Gi
# To: storage: 100Gi

# 3. Save and exit

# 4. Wait for resize (can take a few minutes)
oc get pvc openclaw-data -n openclaw -w

# 5. Verify new size
oc exec -n openclaw deployment/openclaw -- df -h /data
```

**Note**: Most storage classes support online resizing (no pod restart required).

### Changing Storage Class

**Warning**: Cannot change storage class of existing PVC. Must recreate.

```bash
# 1. Backup data first!
oc exec -n openclaw deployment/openclaw -- tar czf /tmp/backup.tar.gz /data

# 2. Copy backup out
oc cp openclaw/$(oc get pod -n openclaw -l app.kubernetes.io/name=openclaw -o name | cut -d/ -f2):/tmp/backup.tar.gz ./backup.tar.gz

# 3. Delete deployment
oc delete deployment openclaw -n openclaw

# 4. Delete PVC
oc delete pvc openclaw-data -n openclaw

# 5. Edit manifests to specify new storage class
# Edit manifests/base/pvc.yaml or use overlay

# 6. Redeploy
./scripts/install.sh production

# 7. Restore data
oc cp ./backup.tar.gz openclaw/$(oc get pod -n openclaw -l app.kubernetes.io/name=openclaw -o name | cut -d/ -f2):/tmp/backup.tar.gz
oc exec -n openclaw deployment/openclaw -- tar xzf /tmp/backup.tar.gz -C /
```

---

## Network Configuration

### Route Configuration

#### Viewing Route

```bash
# Get route details
oc get route openclaw -n openclaw -o yaml
```

#### Custom Hostname

Edit `manifests/production/kustomization.yaml`:

```yaml
patchesStrategicMerge:
- |-
  apiVersion: route.openshift.io/v1
  kind: Route
  metadata:
    name: openclaw
    namespace: openclaw
  spec:
    host: openclaw.yourdomain.com
```

Apply:

```bash
oc apply -k manifests/production
```

#### Custom TLS Certificate

```bash
# Create TLS secret
oc create secret tls openclaw-tls -n openclaw \
  --cert=/path/to/cert.crt \
  --key=/path/to/cert.key

# Update route to use custom cert
oc patch route openclaw -n openclaw --type=merge -p \
  '{"spec":{"tls":{"certificate":"$(cat cert.crt)","key":"$(cat cert.key)"}}}'
```

### Service Configuration

Default service configuration should work for most cases. To customize:

```bash
# Edit service
oc edit service openclaw -n openclaw
```

---

## Security Configuration

### Security Context Constraints (SCC)

#### View Current SCC

```bash
# View SCC
oc get scc openclaw-scc -o yaml

# Check if service account can use SCC
oc auth can-i use scc/openclaw-scc --as=system:serviceaccount:openclaw:openclaw
```

#### Tightening Security

To use a more restrictive SCC (if `openclaw-scc` is too permissive):

```bash
# Try using restricted SCC
oc adm policy add-scc-to-user restricted system:serviceaccount:openclaw:openclaw

# Remove custom SCC
oc delete scc openclaw-scc
oc delete clusterrolebinding openclaw-scc-binding
oc delete clusterrole openclaw-scc-user
```

**Note**: Test thoroughly after changing SCC. OpenClaw requires specific permissions for volume ownership.

### Network Policies

To restrict network access:

```yaml
# Create network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-netpol
  namespace: openclaw
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: openclaw
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          network.openshift.io/policy-group: ingress
    ports:
    - protocol: TCP
      port: 18789
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS for AI APIs
```

Apply:

```bash
oc apply -f network-policy.yaml
```

---

## Environment-Specific Configuration

### Lab Environment

Optimized for fast iteration and testing:

```yaml
# manifests/lab/kustomization.yaml highlights
- Lower resources (500m CPU, 1Gi RAM)
- Smaller storage (20Gi)
- Debug logging enabled
- Latest image tag
- Sandbox mode disabled (faster, less secure)
```

### Production Environment

Hardened for production use:

```yaml
# manifests/production/kustomization.yaml highlights
- Higher resources (2000m+ CPU, 4Gi+ RAM)
- Larger storage (100Gi)
- Info-level logging
- Pinned stable image tag
- Sandbox mode enabled
- Resource guarantees
- Monitoring annotations
```

### Switching Environments

```bash
# Switch from lab to production
oc delete -k manifests/lab
oc apply -k manifests/production

# Or use scripts
./scripts/uninstall.sh --keep-data
./scripts/install.sh production
```

---

## Best Practices

1. **Use Kustomize overlays** for environment differences
2. **Never commit secrets** to Git - use sealed secrets or external secret managers
3. **Pin image tags** in production (don't use `latest`)
4. **Set resource limits** to prevent resource exhaustion
5. **Enable monitoring** in production
6. **Backup configuration** before major changes
7. **Test changes** in lab environment first
8. **Document customizations** in this file or project README

---

## Next Steps

➡️ [Security Guide](security.md) - Harden your deployment
➡️ [Operations Guide](operations.md) - Day-2 operations
➡️ [Troubleshooting](troubleshooting.md) - Common issues

---

## References

- [Deployment Guide](deployment.md)
- [OpenShift Configuration Documentation](https://docs.openshift.com/container-platform/latest/applications/application_life_cycle_management/odc-editing-applications.html)
