# OpenClaw Device Pairing Guide

**Status**: ✅ Operational
**Last Updated**: 2026-03-31

---

## 🔐 What is Device Pairing?

OpenClaw uses a **device pairing system** as a security layer to prevent unauthorized access to your gateway. When you connect to the Control UI from a new browser or device, OpenClaw requires explicit approval before allowing the connection.

This security measure protects your OpenClaw instance from unauthorized access, even if someone knows your Route URL.

---

## 📋 Understanding the "Pairing Required" Error

When you see this error in the Control UI:

```
Disconnected from gateway.
pairing required
```

**This is normal!** It means:
- ✅ CORS is working (no "origin not allowed" error)
- ✅ The WebSocket connection reached the gateway
- ⏳ The device needs to be approved

---

## ✅ How to Approve a New Device

### Step 1: List Pending Pairing Requests

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list
```

**Example output:**
```
Pending (2)
┌──────────────────────────────────────┬──────────────────────────────┬──────────┬────────────────┬──────────┬────────┐
│ Request                              │ Device                       │ Role     │ IP             │ Age      │ Flags  │
├──────────────────────────────────────┼──────────────────────────────┼──────────┼────────────────┼──────────┼────────┤
│ c3e59a22-c179-42f8-a887-d77d0fa00ba0 │ e9af57cd4759d305...          │ operator │                │ just now │        │
│ ce1329c2-432d-4fef-8001-63aff9f7cf25 │ bd4612ca26a6f974...          │ operator │ 78.198.119.124 │ just now │        │
└──────────────────────────────────────┴──────────────────────────────┴──────────┴────────────────┴──────────┴────────┘
```

### Step 2: Approve the Device

Copy the **Request ID** from the first column and approve it:

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- \
  openclaw devices approve c3e59a22-c179-42f8-a887-d77d0fa00ba0
```

**Expected output:**
```
Approved e9af57cd4759d305d02a62af6b109377... (c3e59a22-c179-42f8-a887-d77d0fa00ba0)
```

### Step 3: Refresh the Control UI

Go back to your browser and **reload the page**. The Control UI should now connect successfully!

---

## 🔍 Verify Paired Devices

To see all currently paired devices:

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list
```

**Example output showing paired devices:**
```
Paired (2)
┌───────────────────────────┬────────────┬──────────────────────────────────────┬────────────┬────────────────┐
│ Device                    │ Roles      │ Scopes                               │ Tokens     │ IP             │
├───────────────────────────┼────────────┼──────────────────────────────────────┼────────────┼────────────────┤
│ bd4612ca26a6f974...       │ operator   │ operator.admin, operator.approvals   │ operator   │ 78.198.119.124 │
│ e9af57cd4759d305...       │ operator   │ operator.admin, operator.read        │ operator   │                │
└───────────────────────────┴────────────┴──────────────────────────────────────┴────────────┴────────────────┘
```

---

## 🚀 Quick Pairing Script

For convenience, create a script to automatically approve all pending devices:

```bash
#!/usr/bin/env bash
# approve-all-devices.sh

echo "Listing pending pairing requests..."
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list

echo ""
read -p "Approve all pending requests? (y/N): " confirm

if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    # Get all pending request IDs
    REQUEST_IDS=$(oc exec -n openclaw deployment/openclaw -c openclaw -- \
      openclaw devices list --format json 2>/dev/null | \
      jq -r '.pending[]?.requestId // empty' 2>/dev/null)

    if [ -z "$REQUEST_IDS" ]; then
        echo "No pending requests to approve."
        exit 0
    fi

    for REQUEST_ID in $REQUEST_IDS; do
        echo "Approving $REQUEST_ID..."
        oc exec -n openclaw deployment/openclaw -c openclaw -- \
          openclaw devices approve "$REQUEST_ID"
    done

    echo ""
    echo "✅ All devices approved!"
    echo "Refresh the Control UI in your browser."
else
    echo "Cancelled."
fi
```

**Make it executable:**
```bash
chmod +x approve-all-devices.sh
./approve-all-devices.sh
```

---

## 🔐 Security Best Practices

### 1. Review Before Approving

Always check the **IP address** and **age** of pairing requests before approving:

```bash
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list
```

**Only approve devices you recognize!**

### 2. Remove Compromised Devices

If you suspect a device has been compromised:

```bash
# List all paired devices
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list

# Revoke a specific device
oc exec -n openclaw deployment/openclaw -c openclaw -- \
  openclaw devices revoke <DEVICE_ID>
```

### 3. Monitor Active Connections

Check the OpenClaw logs for active connections:

```bash
oc logs -n openclaw deployment/openclaw -c openclaw --tail=50 | \
  grep -i "webchat connected"
```

---

## 🐛 Troubleshooting

### Problem: "Pairing Required" error persists after approval

**Cause**: Browser cache or old session

**Solution**:
1. Hard refresh the browser (Ctrl+Shift+R or Cmd+Shift+R)
2. Clear browser cache for the OpenClaw site
3. Try incognito/private browsing mode
4. Check that the device was actually approved:
   ```bash
   oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list
   ```

### Problem: Device appears in "Pending" but not my browser

**Cause**: Multiple browser tabs or windows

**Solution**:
- Each browser tab generates a separate pairing request
- Close extra tabs before requesting pairing
- Approve all pending requests if multiple tabs were opened

### Problem: Cannot run `openclaw devices` commands

**Cause**: CLI not available in container

**Solution**:
```bash
# Verify OpenClaw CLI is installed
oc exec -n openclaw deployment/openclaw -c openclaw -- which openclaw

# If not found, check the container image version
oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## 📚 Additional Resources

- [OpenClaw Security Documentation](https://docs.openclaw.ai/gateway/security)
- [Device Pairing Architecture](https://deepwiki.com/openclaw/openclaw/2.2-authentication-and-device-pairing)
- [GitHub Issue #4941](https://github.com/openclaw/openclaw/issues/4941) - Docker pairing issues
- [GitHub Issue #16204](https://github.com/openclaw/openclaw/issues/16204) - Dashboard pairing troubleshooting

---

## 🎯 Summary

| Action | Command |
|--------|---------|
| **List pending requests** | `oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list` |
| **Approve a device** | `oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices approve <REQUEST_ID>` |
| **List paired devices** | `oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list` |
| **Revoke a device** | `oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices revoke <DEVICE_ID>` |

---

**✅ Device pairing is an important security feature that ensures only authorized devices can access your OpenClaw instance!**
