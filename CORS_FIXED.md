# CORS Issue - RESOLVED ✅

**Date Fixed**: 2026-03-31
**Status**: ✅ **RESOLVED**

---

## 🎉 Solution Summary

The CORS "origin not allowed" error has been **successfully resolved** by properly configuring OpenClaw's `openclaw.json` configuration file.

**Key Discovery**: OpenClaw requires configuration via JSON file structure, not environment variables.

---

## ✅ What Was Fixed

### Root Cause

OpenClaw validates WebSocket connections against an explicit `allowedOrigins` list in its configuration. The demo image (`ghcr.io/openclaw/openclaw:2026.3.7`) reads configuration from:
- **File**: `/home/node/.openclaw/openclaw.json` (correct method)
- **NOT from**: Environment variables like `OPENCLAW_GATEWAY_CONTROLUI_ALLOWEDORIGINS`

### The Fix

**File**: `manifests/base/openclaw-app-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-app-config
  namespace: openclaw
data:
  openclaw.json: |
    {
      "gateway": {
        "bind": "lan",
        "auth": {
          "mode": "token",
          "token": "CHANGE_ME_IN_PRODUCTION"
        },
        "controlUi": {
          "enabled": true,
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

**Key Configuration Points**:
1. ✅ **`bind: "lan"`** - Modern bind mode (replaces legacy `0.0.0.0`)
2. ✅ **Nested JSON structure** - Not dotted environment variables
3. ✅ **Exact origin matching** - Full URL with protocol and port
4. ✅ **Authentication token** - Required for WebSocket connections
5. ✅ **trustedProxies** - For nginx sidecar proxy detection

---

## 🔑 Access OpenClaw

### Method 1: Direct Access (Requires Device Pairing)

```
https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com
```

**First-time access**: You'll see "pairing required" error. This is normal! See [Device Pairing](#-device-pairing) section below.

### Method 2: Manual Token Entry

1. Open: `https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com`
2. Click on **Settings** (gear icon)
3. Enter token: `CHANGE_ME_IN_PRODUCTION`
4. Click **Connect**

### Method 3: Port-Forward (Development)

```bash
# Still works as a fallback
./access-openclaw.sh

# Then open: http://localhost:18789/#token=CHANGE_ME_IN_PRODUCTION
```

---

## 🔐 Device Pairing

**Important**: OpenClaw uses device pairing for security. When you first access the Control UI, you'll see:

```
Disconnected from gateway.
pairing required
```

This is **normal and expected**! Here's how to approve your device:

### Step 1: List Pending Pairing Requests

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list
```

### Step 2: Approve Your Device

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- \
  openclaw devices approve <REQUEST_ID>
```

Copy the Request ID from the output of step 1.

### Step 3: Reload the Page

Refresh your browser - you should now be connected!

**📖 For detailed pairing instructions, see [PAIRING.md](PAIRING.md)**

---

## 🔐 Security: Change the Default Token (Optional)

**⚠️ IMPORTANT**: Change the default token before production use!

### Generate a Secure Token

```bash
# Generate 64-character random token
openssl rand -hex 32
```

### Update Token in Kubernetes

```bash
# Set new token
NEW_TOKEN="your-generated-token-here"

# Update secret
oc create secret generic openclaw-secrets -n openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="${NEW_TOKEN}" \
  --dry-run=client -o yaml | oc apply -f -

# Update ConfigMap
oc patch configmap openclaw-app-config -n openclaw \
  --type json \
  -p "[{\"op\":\"replace\",\"path\":\"/data/openclaw.json\",\"value\":\"$(jq -n --arg token "$NEW_TOKEN" '{gateway:{bind:"lan",auth:{mode:"token",token:$token},controlUi:{enabled:true,allowedOrigins:["https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com","http://localhost:18789","http://127.0.0.1:18789"]},trustedProxies:["127.0.0.1","::1","10.0.0.0/8"]}}' | @json)\"}]"

# Restart pod to apply changes
oc delete pod -n openclaw -l app.kubernetes.io/name=openclaw
```

### Access with New Token

```
https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com/#token=YOUR-NEW-TOKEN
```

---

## 📚 References

Based on official OpenClaw documentation and community resources:

- [OpenClaw Control UI Docs](https://docs.openclaw.ai/web/control-ui)
- [GitHub Issue #29809](https://github.com/openclaw/openclaw/issues/29809) - Origin not allowed error
- [OpenClaw Origin Fix Guide](https://openclaw-setup.me/blog/usage-tips/openclaw-origin-not-allowed-fix/)
- [Configuring Gateway on Azure](https://lucaberton.com/blog/configuring-openclaw-gateway-bind-and-control-ui/)

### Key Learnings

1. **Configuration method**: JSON file structure, not environment variables
2. **Bind modes**: Use `"lan"`, `"loopback"`, `"custom"`, `"tailnet"`, or `"auto"` (not IP addresses)
3. **Origin matching**: Exact match required (scheme + domain + port)
4. **No wildcards**: `"*"` is not supported for `allowedOrigins` in production
5. **Authentication**: Token required when binding to non-loopback addresses

---

## 🎯 Deployment Status

| Component | Status | Details |
|-----------|--------|---------|
| **Pod** | ✅ Running | 2/2 containers (openclaw + nginx-proxy) |
| **CORS** | ✅ **FIXED** | allowedOrigins configured in openclaw.json |
| **WebSocket** | ✅ Working | Accepts connections from allowed origins |
| **Route** | ✅ Accessible | https://openclaw-openclaw.apps.rosa... |
| **Authentication** | ✅ Configured | Token-based auth enabled |
| **Nginx Sidecar** | ✅ Operational | Proxying 0.0.0.0:8080 → localhost:18789 |

---

## 🐛 Troubleshooting

### "Disconnected from gateway" Error

**Cause**: Token missing or incorrect

**Solution**: Add `#token=YOUR-TOKEN` to the URL or enter token in UI settings

### "origin not allowed" Error

**Cause**: Origin not in allowedOrigins list

**Solution**:
1. Verify your Route URL matches exactly
2. Update `allowedOrigins` in `openclaw-app-config` ConfigMap
3. Restart pod: `oc delete pod -n openclaw -l app.kubernetes.io/name=openclaw`

### Check Current Configuration

```bash
# View mounted config
oc exec -n openclaw deployment/openclaw -c openclaw -- \
  cat /home/node/.openclaw/openclaw.json

# Check logs for auth errors
oc logs -n openclaw deployment/openclaw -c openclaw --tail=50 | grep -i "origin\|auth"
```

---

## 🎊 Validation

```bash
# Check pod health
oc get pods -n openclaw
# Expected: 2/2 Running

# Test Route
curl -I https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com
# Expected: HTTP/1.1 200 OK

# Check WebSocket logs
oc logs -n openclaw deployment/openclaw -c openclaw --tail=20
# Should NOT show "origin not allowed" errors
```

---

**🎉 OpenClaw is now fully accessible via OpenShift Route with CORS properly configured!**

**Access URL**: https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com/#token=CHANGE_ME_IN_PRODUCTION
