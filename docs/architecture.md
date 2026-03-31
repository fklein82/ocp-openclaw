# Architecture Documentation

Technical architecture documentation for OpenClaw deployment on OpenShift.

## Table of Contents

- [Overview](#overview)
- [Component Architecture](#component-architecture)
- [OpenShift Resource Topology](#openshift-resource-topology)
- [Storage Architecture](#storage-architecture)
- [Network Architecture](#network-architecture)
- [Security Architecture](#security-architecture)
- [High Availability](#high-availability)
- [Scalability Considerations](#scalability-considerations)

---

## Overview

### System Context

```
┌──────────────────────────────────────────────────────────────┐
│                       External Users                          │
│                         (Browser/CLI)                         │
└───────────────────────────┬──────────────────────────────────┘
                            │ HTTPS
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              OpenShift Router (Ingress)                │  │
│  │              TLS Termination (edge)                     │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                   │
│  ┌────────────────────────▼───────────────────────────────┐  │
│  │           Route: openclaw-openclaw.apps...            │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                   │
│  ┌────────────────────────▼───────────────────────────────┐  │
│  │   Service: openclaw (ClusterIP: 18789)                │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                   │
│  ┌────────────────────────▼───────────────────────────────┐  │
│  │        Pod: openclaw-xxxxxxxxx-xxxxx                   │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Container: openclaw                             │  │  │
│  │  │  - Image: ghcr.io/openclaw/openclaw:2026.3.7    │  │  │
│  │  │  - Port: 18789                                   │  │  │
│  │  │  - ConfigMap: openclaw-config                    │  │  │
│  │  │  - Secret: openclaw-secrets                      │  │  │
│  │  │  - Volume: /data → PVC openclaw-data            │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                           │                                   │
│  ┌────────────────────────▼───────────────────────────────┐  │
│  │     PersistentVolumeClaim: openclaw-data (40Gi)       │  │
│  │         ↓                                              │  │
│  │     PersistentVolume (StorageClass: gp3-csi)          │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                   External AI Services                        │
│         (Anthropic, OpenAI, OpenRouter, Google)              │
└──────────────────────────────────────────────────────────────┘
```

### Deployment Pattern

- **Pattern**: Single-replica stateful application
- **Runtime**: Container on OpenShift
- **Storage**: Persistent volume for workspace data
- **Network**: TLS-terminated route for external access
- **Security**: SCC-enforced pod security, RBAC, secrets management

---

## Component Architecture

### Kubernetes/OpenShift Resources

```
Namespace: openclaw
│
├── SecurityContextConstraints (cluster-scoped)
│   └── openclaw-scc
│       • Enforces non-root execution
│       • Allows fsGroup for volume permissions
│
├── ServiceAccount
│   └── openclaw
│       • Identity for pods
│       • Bound to RBAC roles
│
├── RBAC (namespace-scoped)
│   ├── Role: openclaw-role
│   │   • Read: ConfigMaps, Secrets, ServiceAccounts, Pods
│   ├── RoleBinding: openclaw-rolebinding
│   │   • Binds role to ServiceAccount
│   ├── ClusterRole: openclaw-scc-user (cluster-scoped)
│   │   • Allows using openclaw-scc
│   └── ClusterRoleBinding: openclaw-scc-binding (cluster-scoped)
│       • Binds ClusterRole to ServiceAccount
│
├── ConfigMap
│   └── openclaw-config
│       • OPENCLAW_GATEWAY_PORT=18789
│       • OPENCLAW_GATEWAY_BIND=0.0.0.0
│       • OPENCLAW_SANDBOX=1
│       • LOG_LEVEL=info
│
├── Secret
│   └── openclaw-secrets
│       • OPENCLAW_GATEWAY_TOKEN
│       • ANTHROPIC_API_KEY
│       • OPENAI_API_KEY (optional)
│       • Other provider keys
│
├── PersistentVolumeClaim
│   └── openclaw-data
│       • Size: 40Gi (lab) / 100Gi (production)
│       • AccessMode: ReadWriteOnce
│       • StorageClass: <cluster-default>
│
├── Deployment
│   └── openclaw
│       • Replicas: 1
│       • Strategy: Recreate
│       • ServiceAccount: openclaw
│       • Containers:
│           └── openclaw
│               • Image: ghcr.io/openclaw/openclaw:2026.3.7
│               • Port: 18789/TCP
│               • EnvFrom: ConfigMap + Secret
│               • VolumeMount: /data → openclaw-data
│               • SecurityContext: non-root, drop all capabilities
│               • Resources: configurable limits/requests
│               • Probes: startup, liveness, readiness
│
├── Service
│   └── openclaw
│       • Type: ClusterIP
│       • Port: 18789/TCP
│       • Selector: app.kubernetes.io/name=openclaw
│       • SessionAffinity: ClientIP
│
└── Route
    └── openclaw
        • Host: <auto-generated>.apps.<cluster>
        • TLS: edge termination
        • Target: Service openclaw:18789
        • InsecureEdgeTerminationPolicy: Redirect
```

---

## OpenShift Resource Topology

### Resource Relationships

```
┌─────────────────────────────────────────────┐
│         SecurityContextConstraints          │
│              (openclaw-scc)                 │
│   Enforces pod security requirements        │
└─────────────────┬───────────────────────────┘
                  │ can-use
                  ▼
┌─────────────────────────────────────────────┐
│           ServiceAccount (openclaw)         │
│    Identity used by pods                    │
└─────────┬───────────────────────────────────┘
          │ bound-to
          ▼
┌─────────────────────────────────────────────┐
│         Role + RoleBinding                  │
│   Defines namespace permissions             │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│          Deployment (openclaw)              │
│    Manages ReplicaSet and Pods              │
└─────────┬───────────────────────────────────┘
          │ creates
          ▼
┌─────────────────────────────────────────────┐
│       ReplicaSet (auto-managed)             │
│    Ensures desired replica count            │
└─────────┬───────────────────────────────────┘
          │ creates
          ▼
┌─────────────────────────────────────────────┐
│            Pod (openclaw-xxx-yyy)           │
│  ┌───────────────────────────────────────┐  │
│  │   Container: openclaw                 │  │
│  │   • Uses: ServiceAccount              │  │
│  │   • Reads: ConfigMap, Secret          │  │
│  │   • Mounts: PVC                       │  │
│  └───────────────────────────────────────┘  │
└──────────┬──────────────────────────────────┘
           │ matched-by
           ▼
┌─────────────────────────────────────────────┐
│           Service (openclaw)                │
│    Provides stable endpoint                 │
└──────────┬──────────────────────────────────┘
           │ routed-by
           ▼
┌─────────────────────────────────────────────┐
│           Route (openclaw)                  │
│    External HTTPS access                    │
└─────────────────────────────────────────────┘
```

---

## Storage Architecture

### Persistent Volume Layout

```
PersistentVolume (provisioned dynamically)
    │
    ├── Provisioner: kubernetes.io/aws-ebs (example)
    ├── StorageClass: gp3-csi
    ├── Size: 40Gi
    └── Mounted to Pod at: /data
        │
        ├── /data/.openclaw/        (OpenClaw state & config)
        │   ├── config.json
        │   ├── state.db
        │   └── ...
        │
        └── /data/workspace/        (User workspaces)
            ├── project1/
            ├── project2/
            └── ...
```

### Storage Classes by Platform

| Platform | Default StorageClass | Type | Performance |
|----------|---------------------|------|-------------|
| AWS ROSA | `gp3-csi` | AWS EBS gp3 | General purpose SSD |
| Azure ARO | `managed-premium` | Azure Premium SSD | High IOPS |
| GCP | `standard-rwo` | GCE PD | Persistent Disk |
| OpenShift Dedicated | `gp2` or `gp3-csi` | AWS EBS | General purpose |
| On-Premises | Custom | Ceph RBD, NFS, etc. | Varies |

### Volume Access Mode

**Current**: ReadWriteOnce (RWO)
- Volume mounted on single node
- Sufficient for single-replica deployment
- Most efficient (block storage)

**Alternative**: ReadWriteMany (RWX) - for multi-replica
- Volume shared across nodes
- Required for horizontal scaling
- Requires shared filesystem (NFS, CephFS, etc.)

---

## Network Architecture

### Network Flow

```
                    Internet
                       │
                       │ HTTPS (443)
                       ▼
            ┌──────────────────────┐
            │  OpenShift Router    │
            │  (haproxy)           │
            │  • TLS termination   │
            │  • Load balancing    │
            └──────────┬───────────┘
                       │
                       │ HTTP (18789)
                       ▼
            ┌──────────────────────┐
            │  Service (ClusterIP) │
            │  openclaw:18789      │
            │  • Session affinity  │
            └──────────┬───────────┘
                       │
                       │ TCP
                       ▼
            ┌──────────────────────┐
            │  Pod (openclaw)      │
            │  Container port 18789│
            └──────────────────────┘
                       │
                       │ Egress HTTPS (443)
                       ▼
            ┌──────────────────────┐
            │  External AI APIs    │
            │  • api.anthropic.com │
            │  • api.openai.com    │
            └──────────────────────┘
```

### Network Segmentation

```
┌────────────────────────────────────────────────────┐
│              OpenShift Cluster Network             │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │        Ingress Namespace                     │ │
│  │  ┌────────────────────────────────────────┐  │ │
│  │  │   OpenShift Router Pods               │  │ │
│  │  │   (receive external traffic)          │  │ │
│  │  └────────────────────────────────────────┘  │ │
│  └──────────────────┬───────────────────────────┘ │
│                     │ Allowed by default          │
│                     ▼                             │
│  ┌──────────────────────────────────────────────┐ │
│  │        openclaw Namespace                    │ │
│  │  ┌────────────────────────────────────────┐  │ │
│  │  │   openclaw Pod                        │  │ │
│  │  │   • Ingress: 18789 from router        │  │ │
│  │  │   • Egress: 443 to AI APIs            │  │ │
│  │  │   • Egress: 53 to DNS                 │  │ │
│  │  └────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────┘
```

### DNS Resolution

```
Pod → CoreDNS (openshift-dns) → External DNS
  │
  └─ Service discovery: openclaw.openclaw.svc.cluster.local → ClusterIP
```

---

## Security Architecture

### Defense Layers

```
Layer 7: Application
    ├── Authentication: Gateway token
    └── Authorization: API key validation

Layer 6: Route/TLS
    ├── TLS encryption (edge termination)
    └── HTTP → HTTPS redirect

Layer 5: Service
    └── Session affinity (stateful sessions)

Layer 4: Network Policy (optional)
    ├── Ingress: Allow from router only
    └── Egress: Allow to AI APIs + DNS

Layer 3: Pod Security
    ├── SecurityContextConstraints (SCC)
    │   ├── Non-root execution
    │   ├── No privilege escalation
    │   ├── Drop all capabilities
    │   └── fsGroup for volume ownership
    └── SecurityContext
        ├── runAsNonRoot: true
        ├── allowPrivilegeEscalation: false
        └── seccompProfile: RuntimeDefault

Layer 2: RBAC
    ├── ServiceAccount: openclaw
    ├── Role: Read-only ConfigMap/Secret
    └── No cluster-wide permissions

Layer 1: Secrets
    ├── Encrypted at rest (etcd)
    └── Mounted as environment variables
```

### Trust Boundaries

```
┌─────────────────────────────────────────────┐
│         Untrusted Zone (Internet)           │
└───────────────────┬─────────────────────────┘
                    │ TLS (trusted)
                    ▼
┌─────────────────────────────────────────────┐
│    Semi-Trusted Zone (OpenShift Router)     │
└───────────────────┬─────────────────────────┘
                    │ HTTP (internal)
                    ▼
┌─────────────────────────────────────────────┐
│       Trusted Zone (openclaw namespace)     │
│  ┌───────────────────────────────────────┐  │
│  │  Pod: openclaw                        │  │
│  │  • Isolated by namespace              │  │
│  │  • Restricted by SCC                  │  │
│  │  • Limited by RBAC                    │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

---

## High Availability

### Current Design: Single Replica

**Trade-offs**:
- ✅ **Simplicity**: Easy to manage
- ✅ **Cost-effective**: Single replica reduces resource usage
- ✅ **State consistency**: No distributed state concerns
- ⚠️ **Downtime during updates**: 30-60 seconds (Recreate strategy)
- ❌ **Single point of failure**: Node failure causes downtime

### Achieving Higher Availability

#### Option 1: Fast Recovery (Current)

```yaml
Deployment:
  replicas: 1
  strategy: Recreate
PVC:
  accessMode: ReadWriteOnce
```

**Recovery time**:
- Pod crash: ~30 seconds (automatic restart)
- Node failure: ~5 minutes (pod rescheduled to healthy node)

#### Option 2: Active-Standby

```yaml
Deployment:
  replicas: 2
PVC:
  accessMode: ReadWriteMany  # Requires RWX storage
Service:
  sessionAffinity: ClientIP
```

**Challenges**:
- Requires RWX storage (NFS, CephFS, etc.)
- Application must support concurrent access
- More complex

#### Option 3: StatefulSet with Headless Service

```yaml
StatefulSet:
  replicas: 2
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 100Gi
```

**Benefits**:
- Each replica gets own PVC (no RWX needed)
- Stable network identity
- Ordered deployment

**Challenges**:
- More complex
- Application must handle leader election
- Storage costs increase (multiple PVCs)

---

## Scalability Considerations

### Vertical Scaling (Recommended)

**Increase resources for single pod**:

| Metric | Small | Medium | Large | XLarge |
|--------|-------|--------|-------|--------|
| CPU Request | 500m | 1000m | 2000m | 4000m |
| CPU Limit | 2000m | 4000m | 8000m | 16000m |
| Memory Request | 1Gi | 2Gi | 4Gi | 8Gi |
| Memory Limit | 4Gi | 8Gi | 16Gi | 32Gi |
| Storage | 20Gi | 40Gi | 100Gi | 200Gi |

**How to scale**:

```bash
# Increase memory
oc patch deployment openclaw -n openclaw --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "16Gi"}
]'
```

### Horizontal Scaling (Advanced)

**Requirements**:
1. ReadWriteMany (RWX) storage OR StatefulSet with separate PVCs
2. Application-level session management
3. Shared state handling (if applicable)

**Not recommended unless**:
- Workload exceeds single-node capacity
- Strict uptime SLA requires active-active

### Storage Scaling

**Expand PVC** (if StorageClass supports):

```bash
# Edit PVC
oc edit pvc openclaw-data -n openclaw

# Increase size
spec:
  resources:
    requests:
      storage: 100Gi  # Increased from 40Gi

# Wait for expansion (automatic)
oc get pvc openclaw-data -n openclaw -w
```

---

## Platform-Specific Considerations

### AWS ROSA / OSD

- **StorageClass**: `gp3-csi` (AWS EBS)
- **Performance**: 3000 IOPS baseline, burstable
- **Availability Zone**: PVC bound to single AZ
- **Node affinity**: Pod scheduled to same AZ as PVC

### Azure ARO

- **StorageClass**: `managed-premium` (Azure Disk)
- **Performance**: SSD-backed, high IOPS
- **Zone redundancy**: Zone-aware scheduling available

### On-Premises

- **StorageClass**: Varies (Ceph RBD, NFS, etc.)
- **Performance**: Depends on backing storage
- **Considerations**: Ensure storage meets performance requirements (NVMe recommended)

---

## Disaster Recovery Architecture

### Backup Points

```
┌─────────────────────────────────────┐
│    Cluster-Level Backup             │
│    (etcd snapshots)                 │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│    Namespace-Level Backup           │
│    (YAML manifests in Git)          │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│    Configuration Backup             │
│    • ConfigMap                      │
│    • Secret (encrypted)             │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│    Data Backup                      │
│    • PVC snapshots                  │
│    • OR tar/rsync backups           │
└─────────────────────────────────────┘
```

### Recovery Scenarios

| Scenario | RTO | RPO | Method |
|----------|-----|-----|--------|
| Pod failure | < 1 min | None | Automatic (Deployment controller) |
| PVC corruption | < 1 hour | Last snapshot | Restore from VolumeSnapshot |
| Namespace deletion | < 2 hours | Last Git commit | Redeploy from manifests |
| Cluster failure | < 4 hours | Last backup | Deploy to new cluster |

---

## Future Enhancements

Potential architecture improvements:

1. **GitOps Integration**: Argo CD for automated sync
2. **Multi-Replica HA**: StatefulSet with leader election
3. **Observability**: Prometheus metrics, Grafana dashboards
4. **Autoscaling**: HPA based on custom metrics
5. **Multi-Cluster**: Disaster recovery across clusters
6. **Service Mesh**: Istio for advanced traffic management

---

➡️ [Deployment Guide](deployment.md)
➡️ [Operations Guide](operations.md)
➡️ [Security Guide](security.md)
