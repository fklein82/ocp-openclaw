# Known Issue: CORS Origin Not Allowed

**Status**: ✅ **RESOLVED** (2026-03-31)
**Severity**: ~~Medium~~ **FIXED**
**Solution**: See [CORS_FIXED.md](CORS_FIXED.md) for implementation details

> **Note**: This issue has been resolved. The information below is kept for historical reference.

---

## 📋 Issue Description

When accessing OpenClaw via the OpenShift Route, the WebSocket connection fails with:

```
Disconnected from gateway.
origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)
```

**Error in logs**:
```
[ws] closed before connect ...
code=1008 reason=origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)
```

---

## 🔍 Root Cause

OpenClaw has built-in CORS (Cross-Origin Resource Sharing) protection that only allows WebSocket connections from authorized origins. By default, only `localhost` is allowed.

When accessing via:
- ✅ `http://localhost:18789` → Works (default allowed)
- ❌ `https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com` → Blocked (not in allowed list)

---

## 🧪 Attempted Solutions

### ❌ Attempt 1: Environment Variables

```yaml
# ConfigMap
OPENCLAW_GATEWAY_CONTROLUI_ALLOWEDORIGINS: "https://openclaw-openclaw.apps.rosa..."
OPENCLAW_GATEWAY_TRUSTEDPROXIES: "127.0.0.1,::1,10.0.0.0/8"
```

**Result**: Variables set but not recognized by OpenClaw

### ❌ Attempt 2: Configuration File

```bash
# Created /data/.openclaw/config.json
{
  "gateway": {
    "controlUi": {
      "allowedOrigins": ["https://openclaw-openclaw.apps.rosa..."]
    }
  }
}
```

**Result**: File created but not loaded by OpenClaw

### 🔍 Possible Reasons

1. **Demo Image Limitation**: The `ghcr.io/openclaw/openclaw:latest` image may be a demo/example that doesn't support runtime CORS configuration
2. **Wrong Config Method**: OpenClaw may require a different configuration mechanism
3. **Build-time Configuration**: CORS settings may need to be baked into the image at build time
4. **Different Syntax**: Variable names or file structure may be incorrect

---

## ✅ Working Workaround: Port-Forward

**Use port-forward to bypass CORS entirely:**

```bash
# Method 1: Using script
./access-openclaw.sh

# Method 2: Direct command
oc port-forward -n openclaw svc/openclaw 18789:18789

# Method 3: Using Makefile
make port-forward
```

**Then open**: http://localhost:18789

**Why this works**:
- `localhost` is in the default allowed origins list
- No CORS issue because same origin
- Direct connection to the pod

---

## 🎯 Permanent Solutions (TODO)

### Solution 1: Official OpenClaw Documentation

**Action Required**: Check official OpenClaw documentation for:
- Correct environment variable names
- Configuration file location and format
- CORS configuration examples

**Resources**:
- https://docs.openclaw.ai (if exists)
- https://github.com/openclaw/openclaw (check README and issues)

### Solution 2: Build Custom Image

Create a custom OpenClaw image with CORS pre-configured:

```dockerfile
FROM ghcr.io/openclaw/openclaw:2026.3.7

# Copy custom config
COPY config.json /app/config.json

# Or set at build time
ENV OPENCLAW_GATEWAY_CONTROLUI_ALLOWEDORIGINS="*"
```

### Solution 3: Nginx Proxy with Origin Rewrite

Modify nginx sidecar to rewrite the `Origin` header:

```nginx
# In nginx.conf
location / {
    proxy_pass http://openclaw;

    # Rewrite origin to localhost
    proxy_set_header Origin "http://localhost:18789";

    # But this breaks CORS security!
}
```

**⚠️ WARNING**: This breaks CORS protection

### Solution 4: Wildcard Origin (Development Only)

If OpenClaw supports it:

```yaml
env:
- name: OPENCLAW_GATEWAY_CONTROLUI_ALLOWEDORIGINS
  value: "*"  # Allow all origins (INSECURE!)
```

**⚠️ NOT RECOMMENDED FOR PRODUCTION**

---

## 📊 Impact Assessment

| Access Method | Works? | Production Ready? |
|---------------|--------|-------------------|
| **Port-Forward** | ✅ Yes | ❌ No (dev only) |
| **Route (with CORS fix)** | ❌ No (pending) | ✅ Yes (when fixed) |
| **Direct Pod IP** | ✅ Yes (internal) | ❌ No |

---

## 🐛 Debugging Commands

### Check Current Configuration

```bash
# Environment variables
oc exec -n openclaw deployment/openclaw -c openclaw -- env | grep -i openclaw

# Config files
oc exec -n openclaw deployment/openclaw -c openclaw -- find /data -name '*config*'

# Logs
oc logs -n openclaw deployment/openclaw -c openclaw --tail=100 | grep -i origin
```

### Test WebSocket from Browser

Open browser console (F12) and run:

```javascript
// Test WebSocket connection
const ws = new WebSocket('wss://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com');

ws.onopen = () => console.log('✅ Connected!');
ws.onerror = (e) => console.log('❌ Error:', e);
ws.onclose = (e) => console.log('🔴 Closed:', e.code, e.reason);
```

Expected result:
```
🔴 Closed: 1008 origin not allowed
```

---

## 📝 Current Status

- ✅ Route is accessible (HTTP 200)
- ✅ Nginx sidecar working
- ✅ TLS termination working
- ✅ Pod healthy (2/2 containers)
- ❌ WebSocket CORS blocking connection
- ✅ Port-forward workaround functional

---

## 🎯 Recommendation

**For Now**: Use port-forward for development/testing

```bash
./access-openclaw.sh
# Open: http://localhost:18789
```

**For Production**:
1. Research official OpenClaw CORS configuration
2. Build custom image with pre-configured CORS
3. Or wait for official OpenClaw documentation

---

## 🔗 References

- OpenClaw WebSocket implementation (needs official docs)
- OpenShift Routes: https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html
- CORS Specification: https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS

---

**Last Updated**: 2026-03-31
**Tracked In**: GitHub issue #XXX (create if tracking)

---

## 💡 Community Help Needed

If you know the correct way to configure OpenClaw CORS, please:
1. Open a PR with the fix
2. Update this document
3. Share with the community

**Questions?**
- Check `./access-openclaw.sh` for immediate access
- See `CORS_FIX.md` for more debugging steps
