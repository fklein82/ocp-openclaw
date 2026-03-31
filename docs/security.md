# Security Guide

Security best practices and hardening guide for OpenClaw on OpenShift.

## Table of Contents

- [Security Overview](#security-overview)
- [Security Context Constraints](#security-context-constraints)
- [RBAC & Service Accounts](#rbac--service-accounts)
- [Secrets Management](#secrets-management)
- [Network Security](#network-security)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [Container Security](#container-security)
- [Audit & Compliance](#audit--compliance)
- [Production Security Checklist](#production-security-checklist)

---

## Security Overview

### Defense in Depth

OpenClaw deployment implements multiple security layers:

```
┌─────────────────────────────────────────┐
│  External Access (TLS-terminated Route) │
├─────────────────────────────────────────┤
│  Network Policies                        │
├─────────────────────────────────────────┤
│  Service (ClusterIP)                     │
├─────────────────────────────────────────┤
│  Pod Security (SCC, securityContext)     │
├─────────────────────────────────────────┤
│  RBAC (ServiceAccount, Role, RoleBinding)│
├─────────────────────────────────────────┤
│  Secrets (Encrypted at rest)             │
├─────────────────────────────────────────┤
│  Container (Non-root, read-only volumes) │
└─────────────────────────────────────────┘
```

### Security Principles Applied

1. **Least Privilege**: Minimal RBAC permissions, restrictive SCC
2. **Defense in Depth**: Multiple security layers
3. **Secure by Default**: Production defaults are secure
4. **Secrets Isolation**: API keys in encrypted secrets
5. **Network Segmentation**: Network policies limit exposure
6. **Audit Trail**: All actions logged and auditable

---

## Security Context Constraints

### Understanding OpenShift SCC

SCCs control:
- **UID/GID ranges**: Which user IDs pods can run as
- **Capabilities**: Linux capabilities containers can use
- **Volumes**: Which volume types are allowed
- **Host access**: Whether containers can access host resources
- **Privilege**: Whether containers can run privileged

### Custom SCC for OpenClaw

Location: `manifests/base/scc.yaml`

```yaml
# Key security settings
runAsUser:
  type: MustRunAsRange
  uidRangeMin: 1000
  uidRangeMax: 65535
fsGroup:
  type: MustRunAs
  ranges:
  - min: 1000
    max: 65535
allowPrivilegedContainer: false
allowPrivilegeEscalation: false
requiredDropCapabilities:
- ALL
```

**Security features**:
- ✅ **No root**: Must run as non-root user (UID 1000-65535)
- ✅ **No privilege**: Cannot run privileged containers
- ✅ **No capabilities**: All Linux capabilities dropped
- ✅ **No host access**: Cannot access host network, PID, or filesystem
- ✅ **fsGroup support**: Allows volume ownership for persistent storage

### Verifying SCC Assignment

```bash
# Check which SCC is being used
oc get pod -n openclaw -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'

# Should return: openclaw-scc

# Verify service account can use SCC
oc auth can-i use scc/openclaw-scc --as=system:serviceaccount:openclaw:openclaw

# Should return: yes
```

### Alternative: Use Restrictive SCC

If `openclaw-scc` is too permissive for your organization:

```bash
# Try using the restricted SCC
oc adm policy add-scc-to-user restricted system:serviceaccount:openclaw:openclaw

# Remove custom SCC
oc delete scc openclaw-scc
oc delete clusterrolebinding openclaw-scc-binding
oc delete clusterrole openclaw-scc-user

# Restart deployment
oc rollout restart deployment openclaw -n openclaw
```

**Note**: Test thoroughly. OpenClaw may require fsGroup for volume permissions.

---

## RBAC & Service Accounts

### Principle of Least Privilege

OpenClaw uses dedicated ServiceAccount with minimal permissions.

### Namespace-Level RBAC

Location: `manifests/base/rbac.yaml`

**Permissions granted**:

| Resource | Verbs | Justification |
|----------|-------|---------------|
| `configmaps` | `get`, `list`, `watch` | Read configuration |
| `secrets` | `get`, `list`, `watch` | Read API keys |
| `serviceaccounts` | `get` | Self-inspection |
| `pods` | `get`, `list` | Self-inspection |

**Permissions NOT granted**:
- ❌ No `create`, `update`, `delete` on any resources
- ❌ No access to other namespaces
- ❌ No cluster-level permissions (except SCC use)

### Verifying RBAC

```bash
# Check what service account can do
oc auth can-i --list --as=system:serviceaccount:openclaw:openclaw -n openclaw

# Test specific permissions
oc auth can-i get configmaps --as=system:serviceaccount:openclaw:openclaw -n openclaw
# Should return: yes

oc auth can-i delete deployment --as=system:serviceaccount:openclaw:openclaw -n openclaw
# Should return: no
```

### Hardening RBAC

If OpenClaw doesn't need to read ConfigMaps/Secrets at runtime:

```yaml
# Remove unnecessary permissions
# Edit manifests/base/rbac.yaml
rules: []  # Empty rules = no permissions
```

---

## Secrets Management

### Current Approach: Native Kubernetes Secrets

Default deployment uses Kubernetes Secrets:
- ✅ Encrypted at rest (etcd encryption must be enabled on cluster)
- ✅ Only accessible to pods in same namespace with correct RBAC
- ⚠️ Base64 encoded (not encrypted in manifests)

### Viewing Secrets Safely

```bash
# List secrets (safe - doesn't show values)
oc get secrets -n openclaw

# View secret keys (safe - doesn't show values)
oc get secret openclaw-secrets -n openclaw -o jsonpath='{.data}' | jq 'keys'

# UNSAFE: Decode secret value (avoid in shared terminals!)
oc get secret openclaw-secrets -n openclaw -o jsonpath='{.data.ANTHROPIC_API_KEY}' | base64 -d
```

### Best Practices

1. **Never commit secrets to Git**
   ```bash
   # .gitignore includes
   .env
   secrets/
   *.key
   ```

2. **Rotate secrets regularly**
   ```bash
   # Rotate every 90 days
   ./scripts/create-secrets.sh
   ```

3. **Use strong gateway tokens**
   ```bash
   # Generate cryptographically secure token
   openssl rand -hex 32
   ```

4. **Limit secret access**
   ```bash
   # Audit who can read secrets
   oc auth can-i get secrets --as=system:serviceaccount:openclaw:openclaw -n openclaw
   ```

### Advanced: External Secrets Operator

For production, consider external secret management:

#### Option 1: External Secrets Operator (ESO)

```yaml
# Install ESO first: https://external-secrets.io/

apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: openclaw
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "openclaw"

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: openclaw-secrets
  namespace: openclaw
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: openclaw-secrets
  data:
  - secretKey: ANTHROPIC_API_KEY
    remoteRef:
      key: openclaw/api-keys
      property: anthropic
```

#### Option 2: Sealed Secrets

```bash
# Install Sealed Secrets controller
# https://github.com/bitnami-labs/sealed-secrets

# Create sealed secret
kubeseal -o yaml < secret.yaml > sealed-secret.yaml

# Commit sealed-secret.yaml to Git (safe!)
git add sealed-secret.yaml
```

---

## Network Security

### Network Policies

Restrict traffic to/from OpenClaw pods.

#### Example: Default Deny All

```yaml
# network-policy-deny-all.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: openclaw
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

#### Example: Allow Only Ingress and AI APIs

```yaml
# network-policy-openclaw.yaml
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
  # Allow from OpenShift router
  - from:
    - namespaceSelector:
        matchLabels:
          network.openshift.io/policy-group: ingress
    ports:
    - protocol: TCP
      port: 18789
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: openshift-dns
    ports:
    - protocol: UDP
      port: 53
  # Allow HTTPS to AI APIs
  - to:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 443
```

Apply:

```bash
oc apply -f network-policy-openclaw.yaml
```

### Route Security

#### Current Configuration

```yaml
spec:
  tls:
    termination: edge  # TLS terminated at router
    insecureEdgeTerminationPolicy: Redirect  # HTTP → HTTPS redirect
```

**Security features**:
- ✅ TLS encryption in transit
- ✅ Automatic HTTP to HTTPS redirect
- ✅ OpenShift-managed certificates (auto-renewed)

#### Custom TLS Certificate

For production with custom domain:

```bash
# Create TLS secret
oc create secret tls openclaw-tls -n openclaw \
  --cert=path/to/cert.crt \
  --key=path/to/cert.key

# Update route
oc patch route openclaw -n openclaw --type=json -p '[
  {
    "op": "replace",
    "path": "/spec/tls/certificate",
    "value": "'$(cat path/to/cert.crt)'"
  },
  {
    "op": "replace",
    "path": "/spec/tls/key",
    "value": "'$(cat path/to/cert.key)'"
  }
]'
```

---

## TLS/SSL Configuration

### Certificate Management

#### Option 1: OpenShift Default Certificates

- ✅ Automatic issuance and renewal
- ✅ Trusted by browsers (via Let's Encrypt or cluster CA)
- ⚠️ Generic wildcard cert (`*.apps.cluster.example.com`)

**No action required** - works out of the box.

#### Option 2: Custom Certificate

For custom domain (`openclaw.yourdomain.com`):

```bash
# 1. Obtain certificate from CA (Let's Encrypt, DigiCert, etc.)

# 2. Create secret
oc create secret tls openclaw-custom-cert -n openclaw \
  --cert=openclaw.yourdomain.com.crt \
  --key=openclaw.yourdomain.com.key

# 3. Update route to reference secret
oc edit route openclaw -n openclaw
# Add under spec.tls:
#   certificate: <paste cert content>
#   key: <paste key content>
```

#### Option 3: cert-manager Integration

```yaml
# Install cert-manager first
# https://cert-manager.io/docs/installation/

apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openclaw-cert
  namespace: openclaw
spec:
  secretName: openclaw-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - openclaw.yourdomain.com
```

---

## Container Security

### Image Security

#### Use Trusted Images Only

```yaml
# manifests/base/deployment.yaml
spec:
  containers:
  - name: openclaw
    image: ghcr.io/openclaw/openclaw:2026.3.7  # Official image
    imagePullPolicy: IfNotPresent
```

**Best practices**:
- ✅ Use official images from trusted registries
- ✅ Pin specific tags (not `latest` in production)
- ✅ Verify image signatures (if available)
- ⚠️ Scan images for vulnerabilities

#### Image Scanning

```bash
# Scan with OpenShift built-in scanning (if enabled)
oc get images | grep openclaw

# Or use external tools
trivy image ghcr.io/openclaw/openclaw:2026.3.7
```

### Runtime Security

#### Security Context (Pod Level)

```yaml
securityContext:
  fsGroup: 1000
  runAsNonRoot: true
  fsGroupChangePolicy: "OnRootMismatch"
  seccompProfile:
    type: RuntimeDefault
```

#### Security Context (Container Level)

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  runAsNonRoot: true
  # Note: runAsUser is intentionally omitted
  # OpenShift assigns arbitrary UID from namespace range
```

---

## Audit & Compliance

### Audit Logging

#### Enable Audit Logs (Cluster Admin)

OpenShift audit logs capture all API activity:

```bash
# View audit logs (requires cluster-admin)
oc adm must-gather -- /usr/bin/gather_audit_logs

# Query specific events
oc adm audit-trail <pod-name> -n openclaw
```

#### Application Logs

```bash
# View OpenClaw logs
oc logs -f deployment/openclaw -n openclaw

# Export logs for audit
oc logs deployment/openclaw -n openclaw --since=24h > audit-$(date +%Y%m%d).log
```

### Compliance Scanning

Use OpenShift Compliance Operator:

```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: openclaw-compliance
  namespace: openclaw
profiles:
- name: ocp4-cis
  kind: Profile
- name: ocp4-pci-dss
  kind: Profile
settingsRef:
  name: default
  kind: ScanSetting
```

---

## Production Security Checklist

Before going to production:

### Infrastructure

- [ ] Cluster etcd encryption enabled
- [ ] RBAC enabled (default in OpenShift)
- [ ] Network policies defined
- [ ] Default deny-all egress policy
- [ ] Audit logging enabled
- [ ] Monitoring and alerting configured

### OpenClaw Deployment

- [ ] Custom SCC applied and verified
- [ ] RBAC configured with least privilege
- [ ] Secrets rotated from defaults
- [ ] Strong gateway token generated
- [ ] TLS enabled on route
- [ ] Custom TLS certificate (if using custom domain)
- [ ] Resource limits set
- [ ] Non-root container runtime verified
- [ ] Image pinned to specific version (not `latest`)
- [ ] Image scanned for vulnerabilities

### Secrets & Credentials

- [ ] API keys rotated from examples
- [ ] Secrets never committed to Git
- [ ] `.gitignore` includes `.env`, `secrets/`
- [ ] External secret management evaluated
- [ ] Gateway token 32+ characters random
- [ ] API keys stored in encrypted secret manager (production)

### Network

- [ ] Route uses HTTPS with valid certificate
- [ ] HTTP redirects to HTTPS
- [ ] Network policies restrict ingress
- [ ] Network policies restrict egress (allow only AI APIs)
- [ ] Firewall rules allow traffic to route

### Compliance

- [ ] Security scan passed
- [ ] Compliance scan passed
- [ ] Audit logging enabled
- [ ] Log retention policy defined
- [ ] Incident response plan documented

### Documentation

- [ ] Runbook created
- [ ] Escalation contacts defined
- [ ] Disaster recovery plan documented
- [ ] Security contacts defined

---

## Incident Response

### Security Incident Playbook

1. **Detect**: Monitor logs, alerts
2. **Contain**: Isolate affected resources
3. **Investigate**: Analyze logs, events
4. **Remediate**: Patch, rotate secrets, redeploy
5. **Document**: Post-mortem, lessons learned

### Emergency Actions

#### Suspected Compromise

```bash
# 1. Scale down deployment immediately
oc scale deployment openclaw -n openclaw --replicas=0

# 2. Rotate all secrets
./scripts/create-secrets.sh

# 3. Review audit logs
oc logs deployment/openclaw -n openclaw --since=48h > incident-logs.txt

# 4. Review events
oc get events -n openclaw --sort-by='.lastTimestamp' > incident-events.txt

# 5. Redeploy from known-good state
git checkout <last-known-good-commit>
./scripts/install.sh production

# 6. Scale back up after verification
oc scale deployment openclaw -n openclaw --replicas=1
```

---

## References

- [OpenShift Security Best Practices](https://docs.openshift.com/container-platform/latest/security/index.html)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

---

➡️ [Operations Guide](operations.md)
➡️ [Troubleshooting](troubleshooting.md)
