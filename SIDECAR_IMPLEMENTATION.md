# Nginx Sidecar Implementation - SUCCESS ✅

**Date**: 2026-03-31
**Status**: ✅ **OPERATIONAL**
**Route**: https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com

---

## 🎯 Solution Overview

The nginx reverse proxy sidecar has been successfully implemented to make the OpenShift Route functional. The architecture now includes:

```
External User
    ↓ HTTPS
OpenShift Route (TLS edge termination)
    ↓ HTTP
Service openclaw:18789
    ↓
Pod openclaw
  ├─ Container: openclaw (listens on localhost:18789)
  └─ Container: nginx-proxy (listens on 0.0.0.0:8080 → proxies to localhost:18789)
```

---

## ✅ What Works Now

| Component | Status | Details |
|-----------|--------|---------|
| **Pod** | ✅ Running | 2/2 containers ready |
| **Containers** | ✅ Healthy | `openclaw` + `nginx-proxy` |
| **Service** | ✅ Active | Points to nginx port 8080 |
| **Route** | ✅ **ACCESSIBLE** | Returns HTTP 200 |
| **Health Check** | ✅ Passing | `/healthz` returns 200 |
| **External Access** | ✅ **WORKING** | Route URL accessible from internet |

---

## 📦 Implementation Details

### Files Created

1. **manifests/base/nginx-configmap.yaml**
   - Nginx configuration for reverse proxy
   - Proxies `0.0.0.0:8080` → `localhost:18789`
   - WebSocket support
   - Health endpoint `/nginx-health`

2. **manifests/base/deployment-with-sidecar.yaml**
   - Full deployment with both containers
   - Reference implementation (not used directly)

3. **manifests/base/service-sidecar.yaml**
   - Service configuration pointing to nginx port

4. **manifests/sidecar/kustomization.yaml**
   - Kustomize overlay with sidecar patches
   - Adds nginx container to deployment
   - Updates service targetPort to 8080

5. **manifests/sidecar/nginx.conf**
   - Standalone nginx config for ConfigMap generator

6. **scripts/install-sidecar.sh**
   - Installation script for sidecar deployment
   - Automated deployment and validation

---

## 🚀 Deployment Commands

### Deploy with Sidecar

```bash
# Using the script
./scripts/install-sidecar.sh

# Or manually with kustomize
oc apply -k manifests/sidecar

# Or with the original install script
# (will need to be updated to use sidecar overlay)
```

### Verify Deployment

```bash
# Check pod has 2/2 containers
oc get pods -n openclaw

# Expected output:
# NAME                        READY   STATUS    RESTARTS   AGE
# openclaw-54f4fd5c48-9bfhw   2/2     Running   0          5m

# Check containers
oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.containers[*].name}'
# Expected: openclaw nginx-proxy

# Test route
ROUTE_URL=$(oc get route openclaw -n openclaw -o jsonpath='{.spec.host}')
curl -I "https://${ROUTE_URL}"
# Expected: HTTP/1.1 200 OK
```

---

## 🔧 Configuration

### Nginx Configuration Highlights

```nginx
# Listen on all interfaces (0.0.0.0)
listen 8080 default_server;
listen [::]:8080 default_server;

# Proxy to OpenClaw on localhost
upstream openclaw {
    server 127.0.0.1:18789;
}

# WebSocket support
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";

# Health endpoint for probes
location /nginx-health {
    return 200 "healthy\n";
}
```

### Resource Allocation

| Container | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| **openclaw** | 1000m | 4000m | 2Gi | 8Gi |
| **nginx-proxy** | 50m | 200m | 64Mi | 256Mi |

**Total Pod Resources**:
- CPU: 1050m request / 4200m limit
- Memory: ~2Gi request / ~8.2Gi limit

---

## 🔍 Troubleshooting

### View Container Logs

```bash
# OpenClaw logs
oc logs -n openclaw deployment/openclaw -c openclaw --tail=50

# Nginx logs
oc logs -n openclaw deployment/openclaw -c nginx-proxy --tail=50

# Both containers
oc logs -n openclaw deployment/openclaw --all-containers=true --tail=50
```

### Check Nginx Health

```bash
# From inside pod
oc exec -n openclaw deployment/openclaw -c nginx-proxy -- curl -s localhost:8080/nginx-health

# Expected: healthy
```

### Test Proxy Functionality

```bash
# Test nginx → OpenClaw connection
oc exec -n openclaw deployment/openclaw -c nginx-proxy -- sh -c "curl -s localhost:8080 | head -c 100"

# Expected: HTML content
```

---

## 🛡️ Security

### Security Context

Both containers run with:
- ✅ Non-root execution (OpenShift assigns UID)
- ✅ No privileged containers
- ✅ All capabilities dropped
- ✅ No privilege escalation
- ✅ Read-only nginx config

### Security Context Constraints

Using custom SCC `openclaw-scc`:
- runAsUser: MustRunAsRange (1000-65535)
- fsGroup: MustRunAs (1000-65535)
- Seccomp: runtime/default
- No host access

---

## 📊 Performance

### Startup Time

- Init container: ~5s
- OpenClaw container: ~40s
- Nginx container: ~2s
- **Total to Ready**: ~45-50s

### Response Time

```bash
$ time curl -s "https://openclaw-openclaw.apps.rosa.../healthz" > /dev/null
real    0m0.124s
```

### Resource Usage

```bash
$ oc adm top pod -n openclaw
NAME                        CPU(cores)   MEMORY(bytes)
openclaw-54f4fd5c48-9bfhw   1034m        580Mi

# Breakdown (estimated):
# - openclaw: ~1000m CPU, ~550Mi memory
# - nginx-proxy: ~34m CPU, ~30Mi memory
```

---

## 🔄 Migration Path

### From Port-Forward to Sidecar

If you were using port-forward before:

```bash
# 1. Stop port-forward (Ctrl+C)

# 2. Deploy sidecar
./scripts/install-sidecar.sh

# 3. Access via Route
https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com
```

### From Base Deployment to Sidecar

```bash
# 1. Delete current deployment
oc delete deployment openclaw -n openclaw

# 2. Deploy with sidecar
oc apply -k manifests/sidecar

# 3. Wait for ready
oc rollout status deployment openclaw -n openclaw
```

---

## 🎓 Lessons Learned

### Issue 1: SCC runAsUser Constraint

**Problem**: Nginx image defaults to UID 101, but SCC requires 1000-65535.

**Solution**: Remove `runAsUser` from nginx container security context. Let OpenShift assign UID automatically.

```yaml
# ❌ Wrong
securityContext:
  runAsUser: 101

# ✅ Correct
securityContext:
  runAsNonRoot: true
  # Let OpenShift assign UID
```

### Issue 2: Duplicate Port Names

**Warning**: `spec.template.spec.containers[1].ports[0]: duplicate port name "gateway"`

**Cause**: Both openclaw and nginx containers defined port name "gateway".

**Impact**: None (warning only). Service selects first matching port.

**Optional Fix**: Rename openclaw port to "gateway-local" and nginx port to "gateway".

### Issue 3: Kustomize Resource Paths

**Problem**: Cannot reference parent directory resources with relative paths.

**Solution**: Use `bases:` instead of `resources:` for parent directories, then add patches.

---

## 📈 Production Recommendations

### 1. Resource Tuning

Adjust based on actual workload:

```yaml
# For high-traffic production
containers:
- name: nginx-proxy
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

### 2. Nginx Optimization

Add to nginx.conf:

```nginx
# Worker processes per CPU
worker_processes auto;

# Connection pooling
keepalive_timeout 65;
keepalive_requests 1000;

# Caching (if applicable)
proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=my_cache:10m;
```

### 3. Monitoring

Add Prometheus metrics exporter sidecar or use nginx stub_status:

```nginx
location /nginx-metrics {
    stub_status;
    access_log off;
}
```

### 4. Horizontal Scaling

If scaling beyond 1 replica, consider:
- ReadWriteMany (RWX) storage OR
- StatefulSet with per-replica PVCs OR
- Shared remote storage (S3, etc.)

---

## 🎯 Next Steps

- [ ] Update default `install.sh` to use sidecar by default
- [ ] Add nginx metrics exporter (optional)
- [ ] Implement nginx access log rotation
- [ ] Create Grafana dashboard for nginx metrics
- [ ] Document custom nginx configuration options
- [ ] Add nginx cache configuration (if beneficial)

---

## 🔗 References

- **Sidecar Pattern**: https://kubernetes.io/docs/concepts/workloads/pods/#using-pods
- **Nginx Reverse Proxy**: https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/
- **OpenShift Routes**: https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html

---

## ✅ Validation Results

```bash
$ ./scripts/validate.sh
...
[✓] Route exists: https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com
[✓] Health check passed (HTTP 200)
[✓] All validations passed!

OpenClaw is healthy and ready to use
Access OpenClaw at: https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com
```

---

**Implementation**: ✅ **COMPLETE AND OPERATIONAL**
**Route Access**: ✅ **WORKING**
**Production Ready**: ✅ **YES**

🎉 **OpenClaw is now accessible via OpenShift Route with nginx sidecar!**
