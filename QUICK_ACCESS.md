# 🚀 Quick Access Guide

## TL;DR - How to Access OpenClaw Now

```bash
# From your terminal:
./access-openclaw.sh

# Then open in your browser:
http://localhost:18789
```

---

## Why Doesn't the Route Work?

The OpenShift Route (`https://openclaw-openclaw.apps.rosa...com`) returns:
```
Application is not available
```

**Reason**: OpenClaw binds to `127.0.0.1:18789` (localhost only), not `0.0.0.0:18789` (all interfaces).

**Evidence**:
```bash
$ oc logs -n openclaw deployment/openclaw | grep listening
[gateway] listening on ws://127.0.0.1:18789, ws://[::1]:18789
                          ^^^^^^^^^^^
                          localhost only!
```

---

## ✅ Working Solutions

### Method 1: Port-Forward (Easiest)

**One-liner**:
```bash
./access-openclaw.sh
```

**Or manually**:
```bash
oc port-forward -n openclaw svc/openclaw 18789:18789
```

**Or with Make**:
```bash
make port-forward
```

Then open **http://localhost:18789** in your browser.

**How it works**: Creates a tunnel from your laptop → OpenShift → Pod localhost:18789

---

### Method 2: From Another Pod (Testing)

Create a debug pod in the same namespace:

```bash
# Start debug pod
oc run -it --rm debug -n openclaw --image=curlimages/curl --restart=Never -- sh

# Inside the debug pod:
curl http://openclaw:18789
# or
curl http://openclaw.openclaw.svc.cluster.local:18789
```

---

### Method 3: Exec into the Pod

```bash
# Get shell in the pod
oc exec -it -n openclaw deployment/openclaw -- sh

# Test from inside
curl localhost:18789
# Should return HTML content
```

---

## 🔧 Permanent Solutions (For Production)

See **[ROUTE_ACCESS_WORKAROUND.md](ROUTE_ACCESS_WORKAROUND.md)** for:

1. **Configure OpenClaw** to bind to `0.0.0.0` (if supported)
2. **Nginx Sidecar** reverse proxy (works with any version)
3. Full troubleshooting guide

---

## 📋 Verification Checklist

Before accessing, verify deployment is healthy:

```bash
# 1. Check pod is running
oc get pods -n openclaw

# Expected output:
# NAME                        READY   STATUS    RESTARTS   AGE
# openclaw-65bb8cdc5f-xxxxx   1/1     Running   0          10m

# 2. Check logs show app started
oc logs -n openclaw deployment/openclaw --tail=5

# Expected output:
# [gateway] listening on ws://127.0.0.1:18789

# 3. Test from inside pod
oc exec -n openclaw deployment/openclaw -- sh -c "curl -s localhost:18789 | head -c 100"

# Expected: HTML content (<!doctype html>...)
```

✅ **If all checks pass, proceed with port-forward!**

---

## 🎯 Step-by-Step Access Instructions

### Step 1: Verify Connection to OpenShift

```bash
oc whoami
# Should show: cluster-admin (or your username)

oc get pods -n openclaw
# Should show: 1/1 Running
```

### Step 2: Start Port-Forward

**Option A - Using the script** (recommended):
```bash
cd /Users/fklein/Documents/GitHub/ocp-openclaw
./access-openclaw.sh
```

**Option B - Manual command**:
```bash
oc port-forward -n openclaw svc/openclaw 18789:18789
```

**Option C - Using Make**:
```bash
make port-forward
```

You should see:
```
Forwarding from 127.0.0.1:18789 -> 18789
Forwarding from [::1]:18789 -> 18789
```

### Step 3: Open in Browser

Open: **http://localhost:18789**

You should see the OpenClaw interface! 🎉

### Step 4: When Done

Press **Ctrl+C** in the terminal to stop port-forwarding.

---

## 🐛 Troubleshooting Access

### Port-Forward Says "Address already in use"

Something else is using port 18789 on your machine.

**Solution 1 - Use different local port**:
```bash
oc port-forward -n openclaw svc/openclaw 8080:18789
# Then open: http://localhost:8080
```

**Solution 2 - Find and kill the process**:
```bash
# macOS/Linux
lsof -ti:18789 | xargs kill -9

# Then retry port-forward
./access-openclaw.sh
```

### Port-Forward Disconnects Frequently

**Solution**: Use `--address` flag for stability:
```bash
oc port-forward -n openclaw svc/openclaw 18789:18789 --address=127.0.0.1
```

### Can't Connect to localhost:18789

1. **Check port-forward is running**:
   - Look for "Forwarding from 127.0.0.1:18789" message

2. **Check pod is healthy**:
   ```bash
   oc get pods -n openclaw
   oc logs -n openclaw deployment/openclaw --tail=20
   ```

3. **Try pod directly instead of service**:
   ```bash
   POD=$(oc get pod -n openclaw -l app.kubernetes.io/name=openclaw -o name | head -n1)
   oc port-forward -n openclaw $POD 18789:18789
   ```

---

## 📊 Access Methods Comparison

| Method | Works? | Complexity | Use Case |
|--------|--------|-----------|----------|
| **Route** (https://...) | ❌ No | N/A | Doesn't work (app binds localhost) |
| **Port-Forward** | ✅ Yes | ⭐ Easy | Development, testing, demos |
| **Nginx Sidecar** | ✅ Yes | ⭐⭐⭐ Complex | Production deployments |
| **Debug Pod** | ✅ Yes | ⭐⭐ Medium | Testing, troubleshooting |

---

## 🎓 Understanding the Problem

```
┌─────────────────────────────────────────────┐
│  Browser → Route → Service → Pod IP:18789  │  ❌ FAILS
│                               ↓             │
│                    App binds to 127.0.0.1  │
│                    (not listening on       │
│                     pod IP interface)      │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Browser → Port-Forward → Pod localhost:18789│ ✅ WORKS
│                            ↓                │
│                 App binds to 127.0.0.1     │
│                 (listening on localhost)    │
└─────────────────────────────────────────────┘
```

The Route tries to connect to the **pod's IP address** (e.g., 10.129.0.36:18789), but OpenClaw only accepts connections on **localhost** (127.0.0.1:18789).

Port-forward creates a tunnel directly to the pod's localhost, which works!

---

## 🚀 Production Solution Preview

For production, you'll need to either:

### Option A: Configure OpenClaw (if supported)
```yaml
env:
- name: OPENCLAW_BIND_ADDRESS
  value: "0.0.0.0"  # Bind to all interfaces
```

### Option B: Add Nginx Sidecar
```
Route → nginx:8080 → localhost:18789 → OpenClaw
```

Full implementation in **[ROUTE_ACCESS_WORKAROUND.md](ROUTE_ACCESS_WORKAROUND.md)**

---

## 📞 Need Help?

1. Check **[ROUTE_ACCESS_WORKAROUND.md](ROUTE_ACCESS_WORKAROUND.md)** for detailed solutions
2. Check **[docs/troubleshooting.md](docs/troubleshooting.md)** for general issues
3. Run validation: `./scripts/validate.sh`

---

**Quick Start**: `./access-openclaw.sh` → Open `http://localhost:18789` 🎉
