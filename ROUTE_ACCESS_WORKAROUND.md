# Route Access Workaround

## Problem

The OpenShift Route returns **"Application is not available"** when accessed externally.

### Root Cause

OpenClaw binds to `127.0.0.1:18789` (localhost) instead of `0.0.0.0:18789` (all interfaces), making it inaccessible from outside the pod.

**Evidence**:
```bash
$ oc logs -n openclaw deployment/openclaw | grep listening
[gateway] listening on ws://127.0.0.1:18789, ws://[::1]:18789
```

The Route tries to connect to the pod IP (e.g., 10.129.0.36:18789), but the application only accepts connections on localhost.

---

## ✅ Solution 1: Port-Forward (Recommended for Development)

Access OpenClaw directly from your local machine.

### Quick Access

```bash
# Using the provided script
./access-openclaw.sh

# Or manually
oc port-forward -n openclaw svc/openclaw 18789:18789
```

Then open: **http://localhost:18789**

### Makefile Command

```bash
make port-forward
```

### How It Works

Port-forward creates a tunnel: `localhost:18789 → Service → Pod localhost:18789`

This bypasses the Route and connects directly to the pod's localhost interface.

---

## ✅ Solution 2: Configure OpenClaw to Bind 0.0.0.0

If OpenClaw supports binding to all interfaces, configure it.

### Check Configuration Options

```bash
# Check if app has bind configuration
oc exec -n openclaw deployment/openclaw -- env | grep -i bind

# Current output:
OPENCLAW_GATEWAY_BIND=0.0.0.0  # Set but not respected by app
```

### Possible Configuration Methods

1. **Environment Variable** (if supported by newer versions):
   ```yaml
   # In deployment.yaml
   env:
   - name: OPENCLAW_BIND_ADDRESS
     value: "0.0.0.0"
   ```

2. **Command-line Flag** (if supported):
   ```yaml
   # In deployment.yaml
   command:
   - openclaw-gateway
   - --bind
   - "0.0.0.0"
   ```

3. **Config File** (if OpenClaw uses one):
   ```yaml
   # Mount a config file
   server:
     bind: "0.0.0.0"
     port: 18789
   ```

**Action Required**: Check OpenClaw documentation for the correct configuration method.

---

## ✅ Solution 3: Reverse Proxy Sidecar (Production)

Add an nginx sidecar that proxies external traffic to localhost.

### Implementation

Create `manifests/base/deployment-with-sidecar.yaml`:

```yaml
spec:
  template:
    spec:
      containers:
      # Main OpenClaw container (unchanged)
      - name: openclaw
        image: ghcr.io/openclaw/openclaw:2026.3.7
        ports:
        - containerPort: 18789
          name: gateway-local
        # ... rest of config

      # Nginx reverse proxy sidecar
      - name: nginx-proxy
        image: nginxinc/nginx-unprivileged:alpine
        ports:
        - containerPort: 8080
          name: gateway
          protocol: TCP
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop:
            - ALL

      volumes:
      - name: nginx-config
        configMap:
          name: nginx-proxy-config
```

Create `manifests/base/nginx-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-proxy-config
  namespace: openclaw
data:
  nginx.conf: |
    events {
        worker_connections 1024;
    }
    http {
        server {
            listen 8080;
            location / {
                proxy_pass http://127.0.0.1:18789;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }
        }
    }
```

Update `manifests/base/service.yaml`:

```yaml
spec:
  ports:
  - name: gateway
    port: 18789
    targetPort: 8080  # Changed from 18789 to nginx port
```

### Pros & Cons

**Pros**:
- ✅ Works with any OpenClaw version
- ✅ No app reconfiguration needed
- ✅ Production-ready
- ✅ Can add SSL/TLS offloading

**Cons**:
- ❌ Additional complexity
- ❌ Extra resource consumption
- ❌ One more component to manage

---

## ✅ Solution 4: NodePort Service (Testing Only)

Expose via NodePort (not recommended for production).

```yaml
apiVersion: v1
kind: Service
metadata:
  name: openclaw-nodeport
  namespace: openclaw
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: openclaw
  ports:
  - port: 18789
    targetPort: 18789
    nodePort: 30789  # Must be 30000-32767
```

Access via: `http://<node-ip>:30789`

**Note**: Still won't work because app binds to localhost. Only useful if combined with Solution 2.

---

## 🔍 Verification Commands

### Check Application Status

```bash
# Pod is running
oc get pods -n openclaw

# Application logs
oc logs -n openclaw deployment/openclaw --tail=20

# Check listening ports (from inside pod)
oc exec -n openclaw deployment/openclaw -- netstat -tln 2>/dev/null || \
oc exec -n openclaw deployment/openclaw -- ss -tln 2>/dev/null || \
echo "netstat/ss not available"
```

### Test Localhost Access (Inside Pod)

```bash
# Test from inside the pod
oc exec -n openclaw deployment/openclaw -- sh -c "curl -s localhost:18789 | head -c 200"
```

**Expected**: HTML content returned ✅

### Test Service Endpoint

```bash
# Get service IP
SERVICE_IP=$(oc get svc openclaw -n openclaw -o jsonpath='{.spec.clusterIP}')

# Try to connect (will fail)
oc run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v "http://${SERVICE_IP}:18789" --max-time 5
```

**Expected**: Connection refused or timeout ❌

---

## 📊 Comparison of Solutions

| Solution | Complexity | Production Ready | External Access | Notes |
|----------|-----------|------------------|-----------------|-------|
| **Port-Forward** | ⭐ Easy | ❌ No | ❌ Developer only | Best for local testing |
| **Configure App** | ⭐⭐ Medium | ✅ Yes | ✅ Yes | Best if supported |
| **Nginx Sidecar** | ⭐⭐⭐ Complex | ✅ Yes | ✅ Yes | Most flexible |
| **NodePort** | ⭐⭐ Medium | ❌ No | ⚠️ Node access | Not recommended |

---

## 🎯 Recommended Approach

### For Development/Testing
Use **Solution 1 (Port-Forward)**:
```bash
./access-openclaw.sh
# or
make port-forward
```

### For Production

1. **First, try Solution 2**: Check OpenClaw docs for bind configuration
2. **If not supported, use Solution 3**: Deploy nginx sidecar

---

## 📝 Next Steps

1. **Check OpenClaw Documentation**: Look for configuration options to bind to 0.0.0.0
   - GitHub: https://github.com/openclaw/openclaw
   - Docs: https://docs.openclaw.ai

2. **Test Port-Forward**: Verify application functionality
   ```bash
   ./access-openclaw.sh
   ```

3. **Update Documentation**: Once you find the correct configuration method

4. **For Production**: Implement nginx sidecar if app can't bind to 0.0.0.0

---

## 🐛 Troubleshooting

### Port-Forward Fails

```bash
# Check if pod is running
oc get pods -n openclaw

# Check if service exists
oc get svc openclaw -n openclaw

# Use pod directly instead of service
POD_NAME=$(oc get pod -n openclaw -l app.kubernetes.io/name=openclaw -o name | head -n1)
oc port-forward -n openclaw $POD_NAME 18789:18789
```

### Still Can't Access

```bash
# Verify app is actually running
oc logs -n openclaw deployment/openclaw | grep -E "(started|listening|ready)"

# Check from inside pod
oc exec -n openclaw deployment/openclaw -- curl -s localhost:18789 | head -c 100
```

---

## 📚 References

- [OpenShift Routes Documentation](https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html)
- [Kubernetes Port-Forward](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)
- [Sidecar Pattern](https://kubernetes.io/docs/concepts/workloads/pods/#using-pods)

---

**Last Updated**: 2026-03-31
**Status**: Port-forward working ✅, Route requires app reconfiguration or sidecar
