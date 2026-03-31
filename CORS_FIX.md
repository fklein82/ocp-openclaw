# CORS Configuration Fix for OpenClaw Route Access

**Problem**: `origin not allowed` error when accessing OpenClaw via OpenShift Route

**Error Message**:
```
Disconnected from gateway.
origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)
```

---

## 🔍 Root Cause

OpenClaw has CORS (Cross-Origin Resource Sharing) restrictions. By default, it only allows access from `localhost`. When accessing via the OpenShift Route, the origin is different and needs to be explicitly allowed.

**Logs show**:
```
[ws] closed before connect ... origin=https://openclaw-openclaw.apps.rosa...
code=1008 reason=origin not allowed
```

---

## ✅ Solution 1: Environment Variables (Attempted)

I've added these environment variables to the ConfigMap:

```yaml
# manifests/base/configmap.yaml
data:
  OPENCLAW_GATEWAY_CONTROLUI_ALLOWEDORIGINS: "https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com,http://localhost:18789"
  OPENCLAW_GATEWAY_TRUSTEDPROXIES: "127.0.0.1,::1,10.0.0.0/8"
```

**Test**: Reload the page in your browser after the pod restarts.

---

## ✅ Solution 2: Configuration File (If env vars don't work)

If environment variables don't work, OpenClaw may require a configuration file.

### Step 1: Create OpenClaw Config File

Create `manifests/base/openclaw-app-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-app-config
  namespace: openclaw
data:
  config.json: |
    {
      "gateway": {
        "controlUi": {
          "allowedOrigins": [
            "https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com",
            "http://localhost:18789",
            "http://127.0.0.1:18789"
          ]
        },
        "trustedProxies": [
          "127.0.0.1",
          "::1",
          "10.0.0.0/8"
        ]
      }
    }
```

### Step 2: Mount Config in Deployment

Update the deployment to mount this config:

```yaml
# In deployment
spec:
  template:
    spec:
      containers:
      - name: openclaw
        volumeMounts:
        - name: app-config
          mountPath: /app/config.json
          subPath: config.json
          readOnly: true
      volumes:
      - name: app-config
        configMap:
          name: openclaw-app-config
```

### Step 3: Tell OpenClaw to Use Config

Add environment variable pointing to config:

```yaml
env:
- name: OPENCLAW_CONFIG_FILE
  value: "/app/config.json"
```

---

## ✅ Solution 3: Disable CORS Check (Development Only)

**⚠️ NOT RECOMMENDED FOR PRODUCTION**

If this is just for testing:

```yaml
env:
- name: OPENCLAW_DISABLE_ORIGIN_CHECK
  value: "true"
```

---

## ✅ Solution 4: Access via Port-Forward (Workaround)

If the above don't work, use port-forward as a workaround:

```bash
# In one terminal
oc port-forward -n openclaw svc/openclaw 18789:18789

# Open in browser
http://localhost:18789
```

This works because localhost is in the default allowed origins.

---

## 🔍 Debugging

### Check Current Environment Variables

```bash
# See what OpenClaw receives
oc exec -n openclaw deployment/openclaw -c openclaw -- env | grep -i openclaw
```

### Check Logs for Config Loading

```bash
# Watch for config-related messages
oc logs -n openclaw deployment/openclaw -c openclaw --tail=50 | grep -i config
```

### Test WebSocket Connection

```bash
# From browser console (F12)
ws = new WebSocket('wss://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com');
ws.onopen = () => console.log('Connected!');
ws.onerror = (e) => console.log('Error:', e);
ws.onclose = (e) => console.log('Closed:', e.code, e.reason);
```

---

## 📚 OpenClaw Configuration Reference

Based on the error message, OpenClaw configuration uses dotted notation:

| Configuration Path | Environment Variable (Possible) | Description |
|-------------------|--------------------------------|-------------|
| `gateway.controlUi.allowedOrigins` | `OPENCLAW_GATEWAY_CONTROLUI_ALLOWEDORIGINS` | Allowed CORS origins |
| `gateway.trustedProxies` | `OPENCLAW_GATEWAY_TRUSTEDPROXIES` | Trusted proxy IPs |
| `gateway.port` | `OPENCLAW_GATEWAY_PORT` | Gateway port |
| `gateway.bind` | `OPENCLAW_GATEWAY_BIND` | Bind address |

**Note**: The exact variable names depend on OpenClaw's implementation. Check OpenClaw documentation for authoritative naming.

---

## 🎯 Next Steps

1. **Reload the browser** after the pod restart
2. **Check browser console** (F12) for WebSocket errors
3. **Check OpenClaw logs** for connection attempts
4. **Try port-forward** as a workaround
5. **Check OpenClaw documentation** for official config method

---

## 📝 Current Status

✅ ConfigMap updated with CORS variables
✅ Pod restarted
⏳ Waiting for browser test

**Test it now**: Reload https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com

---

## 🐛 Still Not Working?

If none of the above work, the issue might be:

1. **OpenClaw version doesn't support these env vars** - Check OpenClaw docs
2. **Config file is required** - Implement Solution 2
3. **Different variable naming** - Try alternatives:
   - `GATEWAY__CONTROLUI__ALLOWEDORIGINS` (double underscore)
   - `gateway.controlUi.allowedOrigins` (literal dotted notation)
   - JSON in env var: `OPENCLAW_CONFIG='{"gateway":{"controlUi":{"allowedOrigins":[...]}}}'`

---

**Quick Fix**: Use port-forward while investigating:

```bash
./access-openclaw.sh
# Then open: http://localhost:18789
```

This bypasses the CORS issue entirely.
