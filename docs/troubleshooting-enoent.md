# Troubleshooting: ENOENT Workspace Error

## Problem

When accessing OpenClaw, you see errors like:

```
Error: ENOENT: no such file or directory, mkdir '/home/node/.openclaw/workspace'
```

Or in the logs:

```
Error: EROFS: read-only file system, open '/home/node/.openclaw/exec-approvals.json'
```

---

## Root Cause

OpenClaw needs to **write** to the `.openclaw` directory to create:
- `workspace/` directory for project files
- `exec-approvals.json` for command execution approvals
- Other runtime state files

If this directory is mounted as read-only (e.g., from a ConfigMap), OpenClaw cannot function properly.

---

## Solution

The deployment has been updated to use a **writable persistent volume** instead of a read-only ConfigMap mount.

### How It Works

1. **InitContainer** copies `openclaw.json` from ConfigMap to `/data/.openclaw/`
2. **HOME** environment variable is set to `/data`
3. OpenClaw uses `/data/.openclaw/` which is on a **persistent volume** (read-write)

---

## Verification

### 1. Check Pod Status

```bash
oc get pods -n openclaw -l app.kubernetes.io/name=openclaw
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
openclaw-7fc9df4c99-xxxxx   2/2     Running   0          5m
```

### 2. Check InitContainer Logs

```bash
oc logs -n openclaw -l app.kubernetes.io/name=openclaw -c copy-config
```

Expected output:
```
Copying openclaw.json to /data/.openclaw/
Config copied successfully
total 16
drwxr-sr-x.  2 node node 4096 Mar 31 21:32 .
drwxrwsr-x. 10 root node 4096 Mar 31 21:17 ..
-rw-r--r--.  1 node node  447 Mar 31 21:32 openclaw.json
```

### 3. Verify HOME Environment Variable

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- env | grep HOME
```

Expected output:
```
HOME=/data
```

### 4. Check for Errors in Logs

```bash
oc logs -n openclaw deployment/openclaw -c openclaw --tail=100 | grep -i error
```

Expected: **No ENOENT or EROFS errors**

### 5. Verify .openclaw Directory

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- ls -la /data/.openclaw/
```

Expected output:
```
total 16
drwxr-sr-x.  2 node node 4096 Mar 31 21:32 .
drwxrwsr-x. 10 root node 4096 Mar 31 21:17 ..
-rw-r--r--.  1 node node  447 Mar 31 21:32 openclaw.json
```

---

## If You're Still Getting Errors

### Problem: InitContainer Fails

**Symptom**: Pod shows `Init:Error` or `Init:CrashLoopBackOff`

**Debug**:
```bash
oc logs -n openclaw -l app.kubernetes.io/name=openclaw -c copy-config
oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw
```

**Possible Causes**:
- PVC not mounted correctly
- Permissions issue with fsGroup
- ConfigMap `openclaw-app-config` missing

**Fix**:
```bash
# Check PVC
oc get pvc -n openclaw openclaw-data

# Check ConfigMap
oc get configmap -n openclaw openclaw-app-config

# Check SCC
oc get scc openclaw-scc
```

### Problem: Config File Not Found

**Symptom**: OpenClaw starts but can't find config

**Debug**:
```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- ls -la /data/.openclaw/
oc exec -n openclaw deployment/openclaw -c openclaw -- cat /data/.openclaw/openclaw.json
```

**Fix**: Restart the pod to trigger initContainer again:
```bash
oc delete pod -n openclaw -l app.kubernetes.io/name=openclaw
```

### Problem: Permission Denied

**Symptom**: `Error: EACCES: permission denied`

**Debug**:
```bash
# Check pod security context
oc get deployment openclaw -n openclaw -o yaml | grep -A 10 securityContext

# Check actual UID in container
oc exec -n openclaw deployment/openclaw -c openclaw -- id
```

**Expected UID**: Between 1000-65535 (from SCC)

**Fix**: Verify SCC is applied:
```bash
oc describe scc openclaw-scc
oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.securityContext}'
```

---

## Manual Workaround (Emergency)

If the automated fix doesn't work, you can manually create the config:

```bash
# 1. Get the config from ConfigMap
oc get configmap openclaw-app-config -n openclaw -o jsonpath='{.data.openclaw\.json}' > /tmp/openclaw.json

# 2. Copy it to the pod
POD=$(oc get pods -n openclaw -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].metadata.name}')
oc exec -n openclaw $POD -c openclaw -- mkdir -p /data/.openclaw
oc cp /tmp/openclaw.json openclaw/$POD:/data/.openclaw/openclaw.json -c openclaw

# 3. Verify
oc exec -n openclaw $POD -c openclaw -- ls -la /data/.openclaw/
```

---

## Related Issues

- **CORS errors**: See [CORS_FIXED.md](../CORS_FIXED.md)
- **Pairing required**: See [PAIRING.md](../PAIRING.md)
- **General troubleshooting**: See [troubleshooting.md](troubleshooting.md)

---

## Technical Details

### Before Fix (v1.0.0)

```yaml
volumeMounts:
- name: openclaw-app-config
  mountPath: /home/node/.openclaw
  readOnly: true  # ❌ Read-only = can't write
```

### After Fix (v1.0.1+)

```yaml
initContainers:
- name: copy-config
  command:
  - sh
  - -c
  - |
    mkdir -p /data/.openclaw
    cp /config-template/openclaw.json /data/.openclaw/openclaw.json
  volumeMounts:
  - name: openclaw-app-config
    mountPath: /config-template
  - name: data
    mountPath: /data  # ✅ Persistent volume = read-write

containers:
- name: openclaw
  env:
  - name: HOME
    value: "/data"  # ✅ Use writable volume
```

---

## Summary

✅ **Fixed in v1.0.1**
- InitContainer copies config to persistent volume
- HOME=/data uses writable storage
- No more ENOENT or EROFS errors
- Configuration persists across restarts

**Deployment**: Automatically included in `manifests/sidecar/`

**Upgrade**: Run `oc apply -k manifests/sidecar` to get the fix

---

**Issue resolved**: 2026-03-31
**Version**: v1.0.1+
**Commit**: 28c6216
