# Operations Guide

Day-2 operations and maintenance guide for OpenClaw on OpenShift.

## Table of Contents

- [Daily Operations](#daily-operations)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Logging](#logging)
- [Backup & Restore](#backup--restore)
- [Scaling](#scaling)
- [Updates & Upgrades](#updates--upgrades)
- [Maintenance Windows](#maintenance-windows)
- [Disaster Recovery](#disaster-recovery)

---

## Daily Operations

### Health Check Routine

```bash
# Quick health check
make validate

# Or manually
oc get pods -n openclaw
oc get deployment openclaw -n openclaw
oc get route openclaw -n openclaw

# Test endpoint
curl -k https://$(oc get route openclaw -n openclaw -o jsonpath='{.spec.host}')/healthz
```

### Viewing Status

```bash
# Comprehensive status
make status

# Deployment status
oc get deployment openclaw -n openclaw

# Pod status with details
oc get pods -n openclaw -o wide

# Resource usage
oc adm top pod -n openclaw
```

### Accessing Logs

```bash
# Follow logs in real-time
make logs

# Last 100 lines
make logs-tail

# Logs from specific time
oc logs deployment/openclaw -n openclaw --since=1h

# Logs from previous pod (after crash)
make logs-previous
```

---

## Monitoring & Health Checks

### Built-in Health Endpoints

OpenClaw provides three health endpoints:

| Endpoint | Purpose | Probe Type |
|----------|---------|------------|
| `/healthz` | Liveness check | Liveness + Startup |
| `/readyz` | Readiness check | Readiness |
| `/metrics` | Prometheus metrics | Monitoring (optional) |

### Testing Health Endpoints

```bash
# Get route URL
ROUTE_URL=$(oc get route openclaw -n openclaw -o jsonpath='https://{.spec.host}')

# Test health
curl -k ${ROUTE_URL}/healthz
# Expected: HTTP 200 OK

# Test readiness
curl -k ${ROUTE_URL}/readyz
# Expected: HTTP 200 OK
```

### Probe Configuration

Current probe settings (from `manifests/base/deployment.yaml`):

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 18789
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 30  # 5 minutes total

livenessProbe:
  httpGet:
    path: /healthz
    port: 18789
  initialDelaySeconds: 30
  periodSeconds: 30
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /readyz
    port: 18789
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3
```

### Monitoring with Prometheus (Optional)

If Prometheus is available in your cluster:

```yaml
# Add to deployment metadata.annotations
prometheus.io/scrape: "true"
prometheus.io/port: "18789"
prometheus.io/path: "/metrics"
```

---

## Logging

### Viewing Logs

```bash
# Real-time logs
oc logs -f deployment/openclaw -n openclaw

# Last 100 lines
oc logs deployment/openclaw -n openclaw --tail=100

# Logs since specific time
oc logs deployment/openclaw -n openclaw --since=2h

# Logs from all replicas (if scaled)
oc logs -l app.kubernetes.io/name=openclaw -n openclaw --all-containers=true
```

### Log Levels

Configure via ConfigMap:

```bash
# Set to debug
oc patch configmap openclaw-config -n openclaw \
  --type merge \
  -p '{"data":{"LOG_LEVEL":"debug"}}'

# Restart to apply
oc rollout restart deployment openclaw -n openclaw
```

Available levels:
- `debug`: Verbose debugging information
- `info`: Normal operational messages (default)
- `warn`: Warning messages
- `error`: Error messages only

### Log Aggregation

#### Option 1: OpenShift Logging Stack

If cluster has logging operator installed:

```bash
# View logs in Kibana
# Navigate to OpenShift web console → Logging

# Query logs via CLI
oc logs deployment/openclaw -n openclaw --tail=1000 > openclaw.log
```

#### Option 2: External Log Aggregation

Configure external log shipping (Splunk, ELK, etc.):

```yaml
# Add logging sidecar
containers:
- name: log-shipper
  image: fluent/fluent-bit:latest
  volumeMounts:
  - name: logs
    mountPath: /var/log/openclaw
  env:
  - name: FLUENT_ELASTICSEARCH_HOST
    value: "elasticsearch.logging.svc"
```

### Log Retention

Default: Logs retained in pod only (lost on pod deletion)

For persistence, use logging operator or export regularly:

```bash
# Export daily logs (add to cron)
oc logs deployment/openclaw -n openclaw --since=24h > logs/openclaw-$(date +%Y%m%d).log
```

---

## Backup & Restore

### What to Backup

| Component | Location | Backup Method |
|-----------|----------|---------------|
| **Workspace data** | PVC `openclaw-data` | Volume snapshot or rsync |
| **Configuration** | ConfigMap | `oc get configmap -o yaml` |
| **Secrets** | Secret (encrypted) | Secure external storage |
| **Manifests** | Git repository | Git commit/tag |

### Backup Workspace Data

#### Method 1: Volume Snapshot (Recommended)

Prerequisites:
- Cluster has VolumeSnapshot support
- StorageClass supports snapshots

```bash
# Create snapshot
cat <<EOF | oc apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: openclaw-backup-$(date +%Y%m%d)
  namespace: openclaw
spec:
  source:
    persistentVolumeClaimName: openclaw-data
EOF

# List snapshots
oc get volumesnapshot -n openclaw

# Restore from snapshot
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-data-restored
  namespace: openclaw
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 40Gi
  dataSource:
    name: openclaw-backup-20260331
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
```

#### Method 2: tar/rsync Backup

```bash
# Create backup
oc exec deployment/openclaw -n openclaw -- tar czf /tmp/backup.tar.gz /data

# Copy to local machine
oc cp openclaw/$(oc get pod -n openclaw -l app.kubernetes.io/name=openclaw -o name | cut -d/ -f2):/tmp/backup.tar.gz ./openclaw-backup-$(date +%Y%m%d).tar.gz

# Verify backup
tar tzf openclaw-backup-$(date +%Y%m%d).tar.gz | head -n 20
```

### Backup Configuration

```bash
# Backup ConfigMap
oc get configmap openclaw-config -n openclaw -o yaml > backup/configmap-$(date +%Y%m%d).yaml

# Backup all manifests
oc get all,configmap,secret,pvc,route -n openclaw -o yaml > backup/full-backup-$(date +%Y%m%d).yaml
```

### Backup Secrets (Secure)

**Warning**: Secrets contain sensitive data. Encrypt before storing.

```bash
# Export secrets (ENCRYPTED)
oc get secret openclaw-secrets -n openclaw -o yaml | \
  gpg --encrypt --recipient admin@example.com > backup/secrets-$(date +%Y%m%d).yaml.gpg

# Restore secrets (DECRYPT)
gpg --decrypt backup/secrets-20260331.yaml.gpg | oc apply -f -
```

### Restore Procedure

```bash
# 1. Restore namespace
oc create namespace openclaw

# 2. Restore SCC and RBAC
oc apply -f manifests/base/scc.yaml
oc apply -f manifests/base/rbac.yaml
oc apply -f manifests/base/serviceaccount.yaml

# 3. Restore ConfigMap and Secrets
oc apply -f backup/configmap-20260331.yaml
gpg --decrypt backup/secrets-20260331.yaml.gpg | oc apply -f -

# 4. Restore PVC (or use snapshot)
oc apply -f backup/pvc-snapshot.yaml

# 5. Restore application
oc apply -k manifests/production

# 6. Restore data (if using tar backup)
oc cp openclaw-backup-20260331.tar.gz openclaw/$(oc get pod -n openclaw -l app.kubernetes.io/name=openclaw -o name | cut -d/ -f2):/tmp/
oc exec deployment/openclaw -n openclaw -- tar xzf /tmp/openclaw-backup-20260331.tar.gz -C /
```

---

## Scaling

### Current Configuration

Default: **1 replica** (stateful app with RWO volume)

### Vertical Scaling (Resources)

Increase CPU/Memory for single pod:

```bash
# Edit deployment
oc edit deployment openclaw -n openclaw

# Update resources:
#   requests:
#     memory: "8Gi"
#     cpu: "4000m"
#   limits:
#     memory: "32Gi"
#     cpu: "16000m"

# Or use patch
oc patch deployment openclaw -n openclaw --type=json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/memory",
    "value": "8Gi"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "32Gi"
  }
]'
```

### Horizontal Scaling (Replicas)

**Limitation**: OpenClaw uses RWO (ReadWriteOnce) PVC by default.

For multi-replica deployment:

1. **Option A**: Use RWX (ReadWriteMany) storage

```bash
# Change PVC access mode
oc edit pvc openclaw-data -n openclaw
# Update: accessModes: [ReadWriteMany]

# Scale deployment
oc scale deployment openclaw -n openclaw --replicas=3
```

2. **Option B**: Use separate PVCs per replica (StatefulSet)

Requires converting Deployment to StatefulSet (advanced).

---

## Updates & Upgrades

### Update Strategy

Current strategy: **Recreate** (for RWO volumes)

```yaml
spec:
  strategy:
    type: Recreate  # Terminates old pod before creating new
```

**Trade-off**: Brief downtime during update (~30-60 seconds)

### Upgrading OpenClaw Version

#### Step 1: Check Release Notes

Review breaking changes and migration steps.

#### Step 2: Update Image Tag

```bash
# Edit kustomization
vim manifests/production/kustomization.yaml

# Update image tag
images:
- name: ghcr.io/openclaw/openclaw
  newTag: "2026.4.1"  # New version

# Apply
oc apply -k manifests/production
```

#### Step 3: Monitor Rollout

```bash
# Watch deployment
oc rollout status deployment openclaw -n openclaw

# Check logs
oc logs -f deployment/openclaw -n openclaw
```

#### Step 4: Validate

```bash
# Run validation
./scripts/validate.sh

# Test endpoint
curl -k https://$(oc get route openclaw -n openclaw -o jsonpath='{.spec.host}')/healthz
```

### Rollback

If update fails:

```bash
# Rollback to previous version
oc rollout undo deployment openclaw -n openclaw

# Check rollout status
oc rollout status deployment openclaw -n openclaw

# Verify rollback
oc get deployment openclaw -n openclaw -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## Maintenance Windows

### Planned Maintenance Checklist

**Pre-Maintenance**:
1. [ ] Notify users of maintenance window
2. [ ] Backup data (PVC snapshot)
3. [ ] Backup configuration (ConfigMap, Secrets)
4. [ ] Document current state
5. [ ] Prepare rollback plan

**During Maintenance**:
1. [ ] Scale down deployment: `oc scale deployment openclaw -n openclaw --replicas=0`
2. [ ] Perform maintenance (update, resize PVC, etc.)
3. [ ] Scale back up: `oc scale deployment openclaw -n openclaw --replicas=1`
4. [ ] Validate: `./scripts/validate.sh`

**Post-Maintenance**:
1. [ ] Monitor logs for errors
2. [ ] Test functionality
3. [ ] Notify users of completion
4. [ ] Document changes

### Maintenance Commands

```bash
# Enter maintenance mode
oc scale deployment openclaw -n openclaw --replicas=0

# Perform maintenance...

# Exit maintenance mode
oc scale deployment openclaw -n openclaw --replicas=1
oc rollout status deployment openclaw -n openclaw
```

---

## Disaster Recovery

### RTO/RPO Targets

| Scenario | RTO (Recovery Time) | RPO (Data Loss) |
|----------|---------------------|-----------------|
| Pod failure | < 5 minutes (automatic) | None |
| Node failure | < 10 minutes (automatic) | None |
| PVC corruption | < 1 hour (manual restore) | Last backup |
| Namespace deletion | < 2 hours (full restore) | Last backup |
| Cluster failure | < 4 hours (new cluster) | Last backup |

### Disaster Scenarios & Recovery

#### Scenario 1: Pod Deleted

**Recovery**: Automatic (Deployment controller recreates)

```bash
# Verify recovery
oc get pods -n openclaw -w
```

#### Scenario 2: Namespace Accidentally Deleted

**Recovery**: Restore from backup

```bash
# 1. Recreate namespace
oc create namespace openclaw

# 2. Restore from Git
git pull origin main
./scripts/install.sh production

# 3. Restore secrets
gpg --decrypt backup/secrets-latest.yaml.gpg | oc apply -f -

# 4. Restore data from snapshot
oc apply -f backup/pvc-snapshot.yaml
```

#### Scenario 3: Data Corruption

**Recovery**: Restore from backup

```bash
# 1. Scale down
oc scale deployment openclaw -n openclaw --replicas=0

# 2. Delete corrupted PVC
oc delete pvc openclaw-data -n openclaw

# 3. Restore from snapshot
oc apply -f backup/pvc-snapshot.yaml

# 4. Scale back up
oc scale deployment openclaw -n openclaw --replicas=1
```

### Automated Backup Schedule

Create CronJob for automated backups:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: openclaw-backup
  namespace: openclaw
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: openclaw
          containers:
          - name: backup
            image: ghcr.io/openclaw/openclaw:2026.3.7
            command:
            - /bin/sh
            - -c
            - |
              tar czf /tmp/backup-$(date +%Y%m%d).tar.gz /data
              # Upload to S3/Azure Blob/etc.
            volumeMounts:
            - name: data
              mountPath: /data
          volumes:
          - name: data
            persistentVolumeClaim:
              claimName: openclaw-data
          restartPolicy: OnFailure
```

---

## Best Practices

1. **Monitor regularly**: Check health daily
2. **Backup frequently**: Daily automated backups
3. **Test restores**: Validate backups quarterly
4. **Update promptly**: Apply security patches within 30 days
5. **Document changes**: Maintain runbook
6. **Review logs**: Weekly log review for anomalies
7. **Capacity planning**: Monitor resource usage trends
8. **Disaster drills**: Practice recovery procedures

---

## Next Steps

➡️ [Troubleshooting Guide](troubleshooting.md)
➡️ [Security Guide](security.md)

---

## References

- [Deployment Guide](deployment.md)
- [Configuration Guide](configuration.md)
- [OpenShift Administration](https://docs.openshift.com/container-platform/latest/applications/index.html)
