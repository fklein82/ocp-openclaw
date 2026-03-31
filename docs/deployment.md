# Deployment Guide

Complete step-by-step guide for deploying OpenClaw on Red Hat OpenShift.

## Table of Contents

- [Quick Start](#quick-start)
- [Detailed Deployment](#detailed-deployment)
  - [Step 1: Clone Repository](#step-1-clone-repository)
  - [Step 2: Login to OpenShift](#step-2-login-to-openshift)
  - [Step 3: Choose Environment](#step-3-choose-environment)
  - [Step 4: Run Installation](#step-4-run-installation)
  - [Step 5: Configure Secrets](#step-5-configure-secrets)
  - [Step 6: Validate Deployment](#step-6-validate-deployment)
  - [Step 7: Access OpenClaw](#step-7-access-openclaw)
- [Deployment Options](#deployment-options)
- [Manual Deployment](#manual-deployment)
- [Troubleshooting Deployment](#troubleshooting-deployment)

---

## Quick Start

**For impatient users** - fastest path to a working deployment:

```bash
# 1. Login to OpenShift
oc login https://your-cluster:443 --username your-user

# 2. Clone repo
git clone https://github.com/your-org/ocp-openclaw.git
cd ocp-openclaw

# 3. Deploy (lab environment)
./scripts/install.sh lab

# 4. Configure secrets
./scripts/create-secrets.sh

# 5. Validate
./scripts/validate.sh
```

**That's it!** OpenClaw should be running. Get the URL with:

```bash
oc get route openclaw -n openclaw -o jsonpath='https://{.spec.host}'
```

---

## Detailed Deployment

### Step 1: Clone Repository

```bash
# Clone the repository
git clone https://github.com/your-org/ocp-openclaw.git
cd ocp-openclaw

# Verify structure
ls -la
# Expected: manifests/, scripts/, docs/, Makefile, README.md
```

### Step 2: Login to OpenShift

```bash
# Login with username/password
oc login https://api.your-cluster.com:6443 --username cluster-admin

# OR login with token
oc login --token=sha256~xxx --server=https://api.your-cluster.com:6443

# Verify login
oc whoami
oc cluster-info
```

### Step 3: Choose Environment

Two deployment profiles are available:

| Profile | Use Case | Resources | Storage | Features |
|---------|----------|-----------|---------|----------|
| **lab** | Development, testing, demos | Low (1-2 vCPU, 4GB RAM) | 20GB | Debug logs, relaxed security |
| **production** | Production workloads | High (2-8 vCPU, 16GB RAM) | 100GB | Info logs, hardened, monitoring |

**Decision guide**:
- Use **lab** for: POCs, development, learning
- Use **production** for: production workloads, enterprise deployments

### Step 4: Run Installation

#### Option A: Using the Install Script (Recommended)

```bash
# Lab deployment
./scripts/install.sh lab

# Production deployment
./scripts/install.sh production
```

The script will:
1. ✅ Verify prerequisites (oc, cluster access, permissions)
2. ✅ Check storage class availability
3. ✅ Create namespace `openclaw`
4. ✅ Apply Security Context Constraints (SCC)
5. ✅ Deploy all manifests (ServiceAccount, RBAC, ConfigMap, Secret, PVC, Deployment, Service, Route)
6. ✅ Wait for deployment to be ready
7. ✅ Display access information

**Expected output**:

```
================================================
OpenClaw OpenShift Deployment
================================================

[INFO] Deployment environment: lab
[INFO] Checking prerequisites...
[SUCCESS] oc CLI found: v4.14.0
[SUCCESS] Logged in as: cluster-admin
[SUCCESS] Cluster permissions validated
[INFO] Target cluster: https://api.example.com:6443

[INFO] Checking available storage classes...
[SUCCESS] Default storage class: gp3-csi

[INFO] Starting deployment...

[INFO] Creating namespace 'openclaw'...
[SUCCESS] Namespace 'openclaw' created

[INFO] Applying Security Context Constraints...
[SUCCESS] SCC 'openclaw-scc' applied

[INFO] Deploying OpenClaw manifests for environment: lab...
[SUCCESS] Manifests applied successfully

[INFO] Waiting for deployment to be ready...
[INFO] Waiting for deployment... (0/1 replicas ready, 10s elapsed)
[SUCCESS] Deployment is ready (1/1 replicas)

[SUCCESS] ✓ OpenClaw deployed successfully!

================================================
[INFO] Useful commands:
  - View pods:        oc get pods -n openclaw
  - View logs:        oc logs -f deployment/openclaw -n openclaw
  - View events:      oc get events -n openclaw --sort-by='.lastTimestamp'
  - Port forward:     oc port-forward -n openclaw svc/openclaw 18789:18789
  - Shell access:     oc exec -it -n openclaw deployment/openclaw -- /bin/sh
================================================

[WARNING] IMPORTANT: Don't forget to update secrets with actual API keys!
[INFO] Run: ./scripts/create-secrets.sh to set API keys securely

[SUCCESS] Installation complete!
```

#### Option B: Using Makefile

```bash
# Lab deployment
make deploy-lab

# Production deployment
make deploy-prod
```

### Step 5: Configure Secrets

**Critical**: The deployment includes placeholder secrets. You **must** configure real API keys.

```bash
# Run interactive secret configuration
./scripts/create-secrets.sh
```

**Wizard prompts**:

```
================================================
OpenClaw Secret Configuration
================================================

[INFO] This script will help you configure API keys and tokens securely

[INFO] Gateway Token Configuration
  The gateway token is used to authenticate requests to OpenClaw

Generate a random gateway token? (yes/no) [yes]: yes
[SUCCESS] Generated secure gateway token

[INFO] AI Provider API Keys Configuration
  Configure API keys for AI providers (press Enter to skip any)

Anthropic API Key (sk-ant-...): sk-ant-api-xxxxxxxxxxxxx

OpenAI API Key (sk-...): [press Enter to skip]

OpenRouter API Key (sk-or-...): [press Enter to skip]

Google API Key: [press Enter to skip]

[INFO] Creating secret in namespace 'openclaw'...
[SUCCESS] Secret 'openclaw-secrets' created successfully

[INFO] Restarting deployment to pick up new secrets...
[SUCCESS] Deployment restart initiated
[SUCCESS] Rollout completed successfully

================================================
[SUCCESS] ✓ Secrets configuration complete!
================================================

[INFO] Configured secrets:
  ✓ Gateway Token
  ✓ Anthropic API Key

[WARNING] IMPORTANT: Save your gateway token securely!
  Gateway Token: a1b2c3d4e5f6...
```

**Alternative**: Manually create secret

```bash
# Create secret with specific values
oc create secret generic openclaw-secrets \
  -n openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --from-literal=ANTHROPIC_API_KEY="sk-ant-your-key-here" \
  --dry-run=client -o yaml | oc apply -f -

# Restart deployment
oc rollout restart deployment openclaw -n openclaw
```

### Step 6: Validate Deployment

```bash
# Run validation script
./scripts/validate.sh
```

**Expected output (all checks passing)**:

```
================================================
OpenClaw OpenShift Validation
================================================

[INFO] Checking cluster connection...
[✓] Connected to https://api.example.com:6443 as cluster-admin

[✓] Namespace 'openclaw' exists
[✓] Service account 'openclaw' exists
[✓] SCC 'openclaw-scc' exists
[✓] Service account can use SCC 'openclaw-scc'
[✓] RBAC resources configured

[✓] ConfigMap exists
[✓] Secret 'openclaw-secrets' exists
[✓] PVC 'openclaw-data' is Bound
[INFO]   Storage: 40Gi, StorageClass: gp3-csi

[✓] Deployment is ready (1/1 replicas)
[✓] 1 pod(s) running
[✓] Pod 'openclaw-7d9f8b5c4-k2x5n' is Ready

[✓] Service 'openclaw' has endpoints: 10.128.2.45
[✓] Route exists: https://openclaw-openclaw.apps.example.com
[INFO]   TLS termination: edge

[INFO] Testing health endpoint: https://openclaw-openclaw.apps.example.com/healthz
[✓] Health check passed (HTTP 200)

[✓] No warning events found

================================================
[✓] All validations passed!

OpenClaw is healthy and ready to use

Access OpenClaw at: https://openclaw-openclaw.apps.example.com
```

### Step 7: Access OpenClaw

#### Get Route URL

```bash
# Get full URL
oc get route openclaw -n openclaw -o jsonpath='https://{.spec.host}'

# Example output: https://openclaw-openclaw.apps.example.com
```

#### Test Health Endpoint

```bash
# Test health
curl -k https://openclaw-openclaw.apps.example.com/healthz

# Expected: HTTP 200 OK
```

#### Port Forward (for local access)

```bash
# Forward port 18789 to localhost
oc port-forward -n openclaw svc/openclaw 18789:18789

# Access at: http://localhost:18789
```

#### Access via Browser

1. Open browser
2. Navigate to route URL (from step above)
3. Use gateway token if prompted

---

## Deployment Options

### Custom Namespace

Default namespace is `openclaw`. To use a different namespace:

```bash
# Edit manifests/base/namespace.yaml first
# Change: name: openclaw to name: your-namespace

# Edit manifests/base/kustomization.yaml
# Change: namespace: openclaw to namespace: your-namespace

# Deploy
./scripts/install.sh lab
```

### Custom Storage Class

To use a specific storage class:

```bash
# Edit manifests/lab/kustomization.yaml or manifests/production/kustomization.yaml
# Add under patchesStrategicMerge:

- |-
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: openclaw-data
    namespace: openclaw
  spec:
    storageClassName: your-storage-class

# Deploy
./scripts/install.sh lab
```

### Custom Route Hostname

To use a custom domain:

```bash
# Edit manifests/production/kustomization.yaml
# Uncomment and set the host line:

- |-
  apiVersion: route.openshift.io/v1
  kind: Route
  metadata:
    name: openclaw
    namespace: openclaw
  spec:
    host: openclaw.yourdomain.com

# Deploy
./scripts/install.sh production
```

---

## Manual Deployment

If you prefer to deploy step-by-step manually:

```bash
# 1. Create namespace
oc create namespace openclaw

# 2. Apply SCC (requires cluster-admin)
oc apply -f manifests/base/scc.yaml

# 3. Apply base manifests
oc apply -k manifests/base

# 4. OR apply lab overlay
oc apply -k manifests/lab

# 5. OR apply production overlay
oc apply -k manifests/production

# 6. Wait for rollout
oc rollout status deployment openclaw -n openclaw

# 7. Create secrets
./scripts/create-secrets.sh

# 8. Validate
./scripts/validate.sh
```

---

## Troubleshooting Deployment

### Issue: SCC Permission Denied

**Symptom**: Error creating SecurityContextConstraints

**Solution**: You need cluster-admin role. Ask your administrator to apply:

```bash
oc apply -f manifests/base/scc.yaml
oc apply -f manifests/base/rbac.yaml
```

### Issue: PVC Pending

**Symptom**: PVC stuck in `Pending` state

**Diagnosis**:

```bash
oc describe pvc openclaw-data -n openclaw
```

**Common causes**:
- No default storage class
- Insufficient storage quota
- Storage class doesn't exist

**Solution**: Specify storage class manually or ask admin to set default.

### Issue: Pod CrashLoopBackOff

**Symptom**: Pod keeps restarting

**Diagnosis**:

```bash
oc logs -n openclaw deployment/openclaw --tail=100
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw
```

**Common causes**:
- Missing API keys (check secrets)
- Volume mount permission issues (check SCC)
- Image pull errors

### Issue: Route Not Accessible

**Symptom**: Cannot access route URL

**Diagnosis**:

```bash
oc get route openclaw -n openclaw
oc get endpoints openclaw -n openclaw
```

**Solution**: Ensure pod is running and service has endpoints.

---

## Next Steps

After successful deployment:

➡️ [Configuration Guide](configuration.md) - Customize OpenClaw settings
➡️ [Operations Guide](operations.md) - Day-2 operations
➡️ [Security Guide](security.md) - Harden your deployment

---

## References

- [Prerequisites](prerequisites.md)
- [Troubleshooting](troubleshooting.md)
- [Architecture](architecture.md)
