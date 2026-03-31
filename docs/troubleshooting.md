# Troubleshooting Guide

Comprehensive troubleshooting guide for OpenClaw on OpenShift.

## Table of Contents

- [Diagnostic Commands](#diagnostic-commands)
- [Common Issues](#common-issues)
- [Pod Issues](#pod-issues)
- [Storage Issues](#storage-issues)
- [Network Issues](#network-issues)
- [Permission Issues](#permission-issues)
- [Performance Issues](#performance-issues)
- [Getting Help](#getting-help)

---

## Diagnostic Commands

### Quick Diagnostic Script

```bash
# Run validation script (recommended first step)
./scripts/validate.sh

# Or use Makefile
make debug
```

### Manual Diagnostics

```bash
# Check all resources
oc get all,pvc,configmap,secret,route -n openclaw

# Check pod status
oc get pods -n openclaw -o wide

# Describe deployment
oc describe deployment openclaw -n openclaw

# Check events (critical for diagnosing issues)
oc get events -n openclaw --sort-by='.lastTimestamp' | tail -n 20

# Check logs
oc logs deployment/openclaw -n openclaw --tail=100

# Check resource usage
oc adm top pod -n openclaw
```

---

## Common Issues

### Issue: "Pod is in ImagePullBackOff"

**Symptoms**:
```
NAME                        READY   STATUS             RESTARTS   AGE
openclaw-7d9f8b5c4-k2x5n   0/1     ImagePullBackOff   0          2m
```

**Diagnosis**:
```bash
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw | grep -A 5 Events
```

**Common Causes**:
1. **Image doesn't exist**: Wrong image name/tag
2. **Registry authentication**: Private registry requires pull secret
3. **Network issues**: Cannot reach registry

**Solutions**:

1. **Verify image exists**:
```bash
# Check image tag
oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.containers[0].image}'

# Try pulling image locally
podman pull ghcr.io/openclaw/openclaw:2026.3.7
```

2. **Check image pull policy**:
```bash
# Edit deployment
oc edit deployment openclaw -n openclaw

# Verify:
spec:
  template:
    spec:
      containers:
      - imagePullPolicy: IfNotPresent  # or Always
```

3. **Add image pull secret** (if private registry):
```bash
# Create pull secret
oc create secret docker-registry regcred -n openclaw \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<password>

# Add to deployment
oc patch deployment openclaw -n openclaw -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"regcred"}]}}}}'
```

---

### Issue: "Pod is in CrashLoopBackOff"

**Symptoms**:
```
NAME                        READY   STATUS              RESTARTS   AGE
openclaw-7d9f8b5c4-k2x5n   0/1     CrashLoopBackOff    5          5m
```

**Diagnosis**:
```bash
# Check current logs
oc logs deployment/openclaw -n openclaw --tail=50

# Check previous logs (from crashed container)
oc logs deployment/openclaw -n openclaw --previous

# Describe pod for events
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw
```

**Common Causes**:
1. **Missing configuration**: API keys not set
2. **Permission issues**: Cannot write to /data volume
3. **Resource limits**: Out of memory
4. **Application error**: Bug or misconfiguration

**Solutions**:

1. **Check secrets are configured**:
```bash
# Verify secret exists and has keys
oc get secret openclaw-secrets -n openclaw -o jsonpath='{.data}' | jq 'keys'

# Expected: ["ANTHROPIC_API_KEY", "OPENCLAW_GATEWAY_TOKEN", ...]

# If missing, configure:
./scripts/create-secrets.sh
```

2. **Check volume permissions**:
```bash
# Get into pod (if running)
oc exec -it deployment/openclaw -n openclaw -- sh

# Check /data permissions
ls -la /data

# Expected: drwxrwsr-x (writable by pod user)
```

3. **Check SCC**:
```bash
# Verify SCC is applied
oc get scc openclaw-scc

# Verify service account can use SCC
oc auth can-i use scc/openclaw-scc --as=system:serviceaccount:openclaw:openclaw
```

4. **Increase resources**:
```bash
# Check resource usage at crash
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw | grep -A 5 "Last State"

# If OOMKilled, increase memory limits
oc patch deployment openclaw -n openclaw --type=json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "16Gi"
  }
]'
```

---

### Issue: "PVC is in Pending state"

**Symptoms**:
```
NAME             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
openclaw-data    Pending                                      gp3-csi        5m
```

**Diagnosis**:
```bash
# Describe PVC for details
oc describe pvc openclaw-data -n openclaw

# Check events
oc get events -n openclaw --field-selector involvedObject.name=openclaw-data
```

**Common Causes**:
1. **No default StorageClass**: Cluster has no default storage class
2. **Insufficient quota**: Namespace storage quota exceeded
3. **StorageClass doesn't exist**: Wrong storage class name
4. **No available volumes**: Cluster out of storage capacity

**Solutions**:

1. **Check storage classes**:
```bash
# List storage classes
oc get storageclass

# Check which is default
oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

2. **Specify storage class explicitly**:
```bash
# Edit PVC
oc edit pvc openclaw-data -n openclaw

# Add storageClassName
spec:
  storageClassName: gp3-csi  # Use your cluster's storage class
```

3. **Check quota**:
```bash
# Check resource quotas
oc describe quota -n openclaw

# If quota exceeded, increase or delete unused PVCs
oc get pvc -n openclaw
oc delete pvc <unused-pvc> -n openclaw
```

---

### Issue: "Route returns 503 Service Unavailable"

**Symptoms**:
```bash
$ curl -k https://openclaw-openclaw.apps.example.com/healthz
<html><body>503 Service Unavailable</body></html>
```

**Diagnosis**:
```bash
# Check if pod is running
oc get pods -n openclaw

# Check service endpoints
oc get endpoints openclaw -n openclaw

# Check route
oc describe route openclaw -n openclaw
```

**Common Causes**:
1. **No running pods**: Deployment scaled to 0 or pods crashed
2. **Service has no endpoints**: Pods not ready
3. **Selector mismatch**: Service selector doesn't match pod labels

**Solutions**:

1. **Check pod status**:
```bash
# Ensure pods are running
oc get pods -n openclaw

# If no pods, check deployment
oc get deployment openclaw -n openclaw

# Scale up if needed
oc scale deployment openclaw -n openclaw --replicas=1
```

2. **Check readiness probe**:
```bash
# Check if pod is ready
oc get pods -n openclaw

# If not ready, check logs
oc logs deployment/openclaw -n openclaw --tail=50

# Check readiness probe failures
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw | grep -A 10 "Readiness"
```

3. **Verify service endpoints**:
```bash
# Check endpoints
oc get endpoints openclaw -n openclaw

# If no endpoints, verify label selector
oc get service openclaw -n openclaw -o jsonpath='{.spec.selector}'
# Compare with pod labels
oc get pods -n openclaw --show-labels
```

---

## Pod Issues

### Issue: "Pod stuck in Pending"

**Diagnosis**:
```bash
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw
```

**Look for**:
- `FailedScheduling`: No nodes available
- `Insufficient cpu/memory`: Not enough resources
- `PersistentVolumeClaim is not bound`: PVC issue

**Solutions**:

1. **Insufficient resources**:
```bash
# Check node resources
oc describe nodes | grep -A 5 "Allocated resources"

# Reduce resource requests
oc patch deployment openclaw -n openclaw --type=json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/memory",
    "value": "1Gi"
  }
]'
```

2. **PVC not bound**: See [PVC is in Pending state](#issue-pvc-is-in-pending-state)

---

### Issue: "Pod is running but not ready"

**Diagnosis**:
```bash
# Check pod conditions
oc get pod -n openclaw -o jsonpath='{.items[0].status.conditions}' | jq

# Check readiness probe
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw | grep -A 10 Readiness
```

**Common Causes**:
- Readiness probe failing
- Application not listening on expected port
- Startup taking longer than probe timeout

**Solutions**:

1. **Check application is listening**:
```bash
# Exec into pod
oc exec -it deployment/openclaw -n openclaw -- sh

# Check if port is listening
netstat -tlnp | grep 18789
# Or
curl localhost:18789/healthz
```

2. **Increase probe timeouts**:
```bash
oc edit deployment openclaw -n openclaw

# Increase:
readinessProbe:
  initialDelaySeconds: 30  # Increase from 15
  timeoutSeconds: 10       # Increase from 5
  periodSeconds: 15        # Increase from 10
```

---

## Storage Issues

### Issue: "Cannot write to /data directory"

**Symptoms**:
```
Error: EACCES: permission denied, open '/data/.openclaw/config.json'
```

**Diagnosis**:
```bash
# Check volume mount
oc exec deployment/openclaw -n openclaw -- ls -la /data

# Check pod security context
oc get pod -n openclaw -o jsonpath='{.items[0].spec.securityContext}' | jq

# Check actual UID running in pod
oc exec deployment/openclaw -n openclaw -- id
```

**Solutions**:

1. **Verify fsGroup is set**:
```bash
oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.securityContext}' | jq

# Should include: "fsGroup": 1000
```

2. **Apply correct SCC**:
```bash
# Ensure SCC allows fsGroup
oc get scc openclaw-scc -o yaml | grep -A 5 fsGroup

# Re-apply SCC if needed
oc apply -f manifests/base/scc.yaml

# Restart pod
oc delete pod -n openclaw -l app.kubernetes.io/name=openclaw
```

---

## Network Issues

### Issue: "Cannot reach external AI APIs"

**Symptoms**:
```
Error: connect ETIMEDOUT <AI provider IP>:443
```

**Diagnosis**:
```bash
# Test from pod
oc exec deployment/openclaw -n openclaw -- curl -I https://api.anthropic.com
oc exec deployment/openclaw -n openclaw -- curl -I https://api.openai.com
```

**Common Causes**:
- Network policies blocking egress
- Corporate proxy required
- Firewall rules

**Solutions**:

1. **Check network policies**:
```bash
# List network policies
oc get networkpolicy -n openclaw

# If policies exist, ensure egress to HTTPS is allowed
```

2. **Configure proxy** (if required):
```bash
# Add to deployment env
oc patch deployment openclaw -n openclaw --type=json -p '[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {"name": "HTTP_PROXY", "value": "http://proxy.corp.com:8080"}
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {"name": "HTTPS_PROXY", "value": "http://proxy.corp.com:8080"}
  }
]'
```

---

## Permission Issues

### Issue: "Forbidden: User cannot create SecurityContextConstraints"

**Symptoms**:
```
Error from server (Forbidden): securitycontextconstraints.security.openshift.io is forbidden:
User "developer" cannot create resource "securitycontextconstraints" in API group "security.openshift.io" at the cluster scope
```

**Solution**:

This requires cluster-admin permissions. Options:

1. **Ask cluster administrator** to apply SCC:
```bash
# Provide to admin:
oc apply -f manifests/base/scc.yaml
oc apply -f manifests/base/rbac.yaml
```

2. **Skip SCC** and use default (may not work):
```bash
# Remove SCC from kustomization
oc apply -k manifests/base --prune-whitelist=core/v1/Secret
```

---

## Performance Issues

### Issue: "OpenClaw is slow or unresponsive"

**Diagnosis**:
```bash
# Check resource usage
oc adm top pod -n openclaw

# Check if resource limits are being hit
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw | grep -A 5 "Limits"

# Check for throttling
oc get pod -n openclaw -o jsonpath='{.items[0].status}' | jq '.containerStatuses[0]'
```

**Solutions**:

1. **Increase CPU limits**:
```bash
oc patch deployment openclaw -n openclaw --type=json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/cpu",
    "value": "8000m"
  }
]'
```

2. **Increase memory**:
```bash
oc patch deployment openclaw -n openclaw --type=json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "16Gi"
  }
]'
```

3. **Check storage performance**:
```bash
# Run I/O test in pod
oc exec deployment/openclaw -n openclaw -- dd if=/dev/zero of=/data/test.img bs=1M count=1000 oflag=direct
```

---

## Getting Help

### Collecting Diagnostic Information

Before seeking help, collect:

```bash
# 1. Validation report
./scripts/validate.sh > diagnostics.txt 2>&1

# 2. Describe all resources
oc describe all,pvc,configmap,route -n openclaw >> diagnostics.txt

# 3. Events
oc get events -n openclaw --sort-by='.lastTimestamp' >> diagnostics.txt

# 4. Logs
oc logs deployment/openclaw -n openclaw --tail=200 >> diagnostics.txt

# 5. Resource usage
oc adm top pod -n openclaw >> diagnostics.txt

# Share diagnostics.txt when seeking help
```

### Support Channels

1. **Internal**: Contact platform team
2. **OpenClaw Community**: [OpenClaw GitHub Discussions](https://github.com/openclaw/openclaw/discussions)
3. **Red Hat Support**: For OpenShift-specific issues

### Reporting Bugs

Include:
- OpenShift version: `oc version`
- OpenClaw version: `oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.containers[0].image}'`
- Diagnostics output (sanitized of secrets!)
- Steps to reproduce
- Expected vs actual behavior

---

## Advanced Troubleshooting

### Enable Debug Logging

```bash
# Set LOG_LEVEL to debug
oc patch configmap openclaw-config -n openclaw --type merge -p '{"data":{"LOG_LEVEL":"debug"}}'

# Restart
oc rollout restart deployment openclaw -n openclaw

# View debug logs
oc logs -f deployment/openclaw -n openclaw
```

### Interactive Debugging

```bash
# Get shell in running pod
oc exec -it deployment/openclaw -n openclaw -- /bin/sh

# Inside pod:
# - Check environment: env | grep OPENCLAW
# - Check filesystem: ls -la /data
# - Check network: curl localhost:18789/healthz
# - Check processes: ps aux
```

### Must-Gather for OpenShift

```bash
# Collect cluster-wide diagnostics
oc adm must-gather --dest-dir=./must-gather

# Compress and share
tar czf must-gather-$(date +%Y%m%d).tar.gz must-gather/
```

---

## Quick Reference

| Symptom | First Check | Quick Fix |
|---------|-------------|-----------|
| Pod not starting | `oc describe pod` | Check logs and events |
| 503 on route | `oc get endpoints` | Ensure pod is ready |
| PVC pending | `oc get storageclass` | Specify storage class |
| Permission denied | `oc get scc` | Apply correct SCC |
| Out of memory | `oc adm top pod` | Increase memory limits |
| Slow performance | `oc adm top pod` | Increase CPU limits |

---

➡️ [Operations Guide](operations.md)
➡️ [Deployment Guide](deployment.md)
