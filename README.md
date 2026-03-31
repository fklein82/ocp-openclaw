# OpenClaw on Red Hat OpenShift

Production-ready deployment of [OpenClaw AI Agent](https://openclaw.ai) on Red Hat OpenShift Container Platform.

[![OpenShift](https://img.shields.io/badge/OpenShift-4.10+-EE0000?logo=redhat&logoColor=white)](https://www.openshift.com/)
[![Kustomize](https://img.shields.io/badge/Kustomize-enabled-blue)](https://kustomize.io/)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

---

## 🚀 Quick Start

Deploy OpenClaw to OpenShift in 3 commands:

```bash
# 1. Login to your OpenShift cluster
oc login https://your-cluster:443 --username your-user

# 2. Clone and deploy
git clone https://github.com/your-org/ocp-openclaw.git
cd ocp-openclaw
./scripts/install.sh lab

# 3. Configure API keys
./scripts/create-secrets.sh
```

Access OpenClaw:
```bash
# ✅ Route fully functional with CORS and authentication configured!
# Get the access URL:
oc get route openclaw -n openclaw -o jsonpath='https://{.spec.host}'

# Or open directly:
# https://openclaw-openclaw.apps.rosa.h7865-k2q99-26s.qpi4.p3.openshiftapps.com
```

**First-time access**: You'll see "pairing required" - this is normal! Approve your device:
```bash
# List pending pairing requests
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices list

# Approve the device (use Request ID from above)
oc exec -n openclaw deployment/openclaw -c openclaw -- openclaw devices approve <REQUEST_ID>

# Refresh your browser - you're connected! 🎉
```

**Note**:
- Default deployment uses nginx reverse proxy sidecar for Route access
- CORS is configured via `openclaw.json` configuration file
- Device pairing required for security (first-time only per device)
- See [PAIRING.md](PAIRING.md) for device pairing guide
- See [CORS_FIXED.md](CORS_FIXED.md) for CORS configuration details
- See [SIDECAR_IMPLEMENTATION.md](SIDECAR_IMPLEMENTATION.md) for architecture details

---

## 📋 Table of Contents

- [Features](#-features)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Operations](#-operations)
- [Documentation](#-documentation)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## ✨ Features

### OpenShift-Native Deployment

- ✅ **Security Context Constraints (SCC)**: Custom SCC for proper permissions
- ✅ **Routes**: TLS-terminated external access (not Ingress)
- ✅ **RBAC**: Least-privilege service account
- ✅ **Kustomize**: Environment-specific overlays (lab/production)
- ✅ **Persistent Storage**: Workspace data on PVCs
- ✅ **Health Checks**: Startup, liveness, and readiness probes

### Production-Ready

- ✅ **Automated Installation**: Idempotent scripts with validation
- ✅ **Security Hardening**: Non-root, read-only root filesystem, no capabilities
- ✅ **Backup & Restore**: Volume snapshot support
- ✅ **Monitoring**: Prometheus-compatible health endpoints
- ✅ **GitOps Ready**: Argo CD application manifests included

### Two Deployment Profiles

| Profile | Use Case | Resources | Storage |
|---------|----------|-----------|---------|
| **lab** | Development, testing, POC | 1-2 vCPU, 4GB RAM | 20GB |
| **production** | Production workloads | 2-8 vCPU, 16GB RAM | 100GB |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                 External Users                       │
│                   (HTTPS/443)                        │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│              OpenShift Router                        │
│         (TLS Edge Termination)                       │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│   Route → Service → Pod (openclaw)                  │
│                                                      │
│   ┌──────────────────────────────────────────────┐  │
│   │  OpenClaw Container                          │  │
│   │  • Port: 18789                               │  │
│   │  • ConfigMap: Configuration                  │  │
│   │  • Secret: API Keys                          │  │
│   │  • Volume: /data (PVC 40-100GB)             │  │
│   └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│            External AI Services                      │
│    (Anthropic, OpenAI, OpenRouter, Google)          │
└─────────────────────────────────────────────────────┘
```

**Key Components**:
- **Namespace**: `openclaw`
- **ServiceAccount**: `openclaw` (least-privilege RBAC)
- **SCC**: `openclaw-scc` (non-root, fsGroup support)
- **Deployment**: Single replica (Recreate strategy)
- **Service**: ClusterIP with session affinity
- **Route**: HTTPS with auto-generated cert
- **PVC**: ReadWriteOnce, 40-100GB

See [Architecture Documentation](docs/architecture.md) for details.

---

## 📦 Prerequisites

### Required

- **OpenShift Cluster**: 4.10+ (OCP, OSD, ROSA, ARO)
- **OpenShift CLI**: `oc` 4.10+
- **Permissions**: Cluster-admin or namespace creation + SCC privileges
- **Storage**: Available StorageClass with at least 40GB
- **AI Provider API Key**: At least one (Anthropic, OpenAI, etc.)

### Recommended

- `kustomize` (optional - `oc` has built-in support)
- `jq` for JSON processing
- `make` for convenience commands

**Detailed requirements**: [Prerequisites Documentation](docs/prerequisites.md)

---

## 🔧 Installation

### Method 1: Automated Script (Recommended)

```bash
# Lab environment (low resources, debug logging)
./scripts/install.sh lab

# Production environment (high resources, hardened)
./scripts/install.sh production
```

### Method 2: Makefile

```bash
# Lab deployment
make deploy-lab

# Production deployment
make deploy-prod

# View all targets
make help
```

### Method 3: Manual Kustomize

```bash
# Create namespace
oc create namespace openclaw

# Apply SCC (requires cluster-admin)
oc apply -f manifests/base/scc.yaml

# Deploy lab environment
oc apply -k manifests/lab

# OR deploy production environment
oc apply -k manifests/production
```

### Post-Installation

```bash
# Configure API keys (interactive)
./scripts/create-secrets.sh

# Validate deployment
./scripts/validate.sh

# Get access URL
oc get route openclaw -n openclaw -o jsonpath='https://{.spec.host}'
```

**Step-by-step guide**: [Deployment Documentation](docs/deployment.md)

---

## ⚙️ Configuration

### ConfigMap (Application Settings)

Edit `manifests/base/configmap.yaml` or patch at runtime:

```bash
# Enable debug logging
oc patch configmap openclaw-config -n openclaw \
  --type merge \
  -p '{"data":{"LOG_LEVEL":"debug"}}'

# Restart to apply
oc rollout restart deployment openclaw -n openclaw
```

### Secrets (API Keys)

Use the provided script for secure secret management:

```bash
# Interactive configuration
./scripts/create-secrets.sh

# Or manually
oc create secret generic openclaw-secrets -n openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --from-literal=ANTHROPIC_API_KEY="sk-ant-your-key" \
  --dry-run=client -o yaml | oc apply -f -
```

### Resource Limits

Edit `manifests/production/kustomization.yaml`:

```yaml
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: openclaw
  spec:
    template:
      spec:
        containers:
        - name: openclaw
          resources:
            limits:
              memory: "16Gi"
              cpu: "8000m"
```

**Complete configuration guide**: [Configuration Documentation](docs/configuration.md)

---

## 🔄 Operations

### Daily Operations

```bash
# Check status
make status

# View logs
make logs

# Validate health
make validate

# Access shell
make shell

# Port forward to localhost
make port-forward
```

### Backup

```bash
# Volume snapshot (if supported)
oc create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: openclaw-backup-$(date +%Y%m%d)
  namespace: openclaw
spec:
  source:
    persistentVolumeClaimName: openclaw-data
EOF

# Or tar backup
oc exec deployment/openclaw -n openclaw -- tar czf /tmp/backup.tar.gz /data
oc cp openclaw/<pod-name>:/tmp/backup.tar.gz ./backup-$(date +%Y%m%d).tar.gz
```

### Updates

```bash
# Update image version
# Edit manifests/production/kustomization.yaml
images:
- name: ghcr.io/openclaw/openclaw
  newTag: "2026.4.1"  # New version

# Apply update
oc apply -k manifests/production

# Monitor rollout
oc rollout status deployment openclaw -n openclaw
```

### Uninstall

```bash
# Remove everything except PVC (preserves data)
./scripts/uninstall.sh --keep-data

# Complete removal (including data)
./scripts/uninstall.sh
```

**Complete operations guide**: [Operations Documentation](docs/operations.md)

---

## 📚 Documentation

Comprehensive documentation in [`docs/`](docs/) directory:

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Requirements and pre-installation checklist |
| [Deployment](docs/deployment.md) | Step-by-step installation guide |
| [Configuration](docs/configuration.md) | ConfigMap, Secrets, resources, storage |
| [Security](docs/security.md) | SCC, RBAC, TLS, secrets management, compliance |
| [Operations](docs/operations.md) | Day-2 ops, monitoring, backup, updates, DR |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |
| [Architecture](docs/architecture.md) | Technical architecture and design decisions |

---

## 🎉 Production-Ready Features

### Nginx Reverse Proxy Sidecar

✅ **Route access is now fully functional** thanks to nginx sidecar!

The deployment includes an nginx reverse proxy that:
- Listens on `0.0.0.0:8080` (all interfaces)
- Proxies to OpenClaw on `localhost:18789`
- Enables external Route access
- Provides WebSocket support
- Adds health check endpoint

**Architecture**:
```
External → Route (TLS) → Service → nginx:8080 → localhost:18789 → OpenClaw
```

See [SIDECAR_IMPLEMENTATION.md](SIDECAR_IMPLEMENTATION.md) for complete details.

### Alternative: Port-Forward (for development)

For local development without sidecar:
```bash
./access-openclaw.sh  # or: make port-forward
```

---

## 🔍 Troubleshooting

### Quick Diagnostics

```bash
# Run automated validation
./scripts/validate.sh

# Or debug manually
make debug
```

### Common Issues

| Problem | Quick Fix |
|---------|-----------|
| Pod not starting | `oc describe pod -n openclaw -l app.kubernetes.io/name=openclaw` |
| Route returns 503 | Check pod is Ready: `oc get pods -n openclaw` |
| PVC stuck Pending | Verify StorageClass: `oc get storageclass` |
| Permission denied | Apply SCC: `oc apply -f manifests/base/scc.yaml` |

**Complete troubleshooting guide**: [Troubleshooting Documentation](docs/troubleshooting.md)

---

## 🛠️ Repository Structure

```
ocp-openclaw/
├── README.md                    # This file
├── Makefile                     # Convenience commands
├── .env.example                 # Configuration template
├── .gitignore                   # Git ignore rules
├── manifests/                   # Kubernetes/OpenShift manifests
│   ├── base/                    # Base manifests (Kustomize)
│   │   ├── namespace.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── scc.yaml
│   │   ├── rbac.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   ├── pvc.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── route.yaml
│   │   └── kustomization.yaml
│   ├── lab/                     # Lab overlay
│   │   └── kustomization.yaml
│   └── production/              # Production overlay
│       └── kustomization.yaml
├── scripts/                     # Automation scripts
│   ├── install.sh               # Installation script
│   ├── uninstall.sh             # Uninstallation script
│   ├── validate.sh              # Health validation script
│   └── create-secrets.sh        # Secret configuration script
├── docs/                        # Documentation
│   ├── prerequisites.md
│   ├── deployment.md
│   ├── configuration.md
│   ├── security.md
│   ├── operations.md
│   ├── troubleshooting.md
│   └── architecture.md
├── examples/                    # Example configurations
│   ├── values-lab.yaml
│   └── values-production.yaml
└── argocd/                      # GitOps manifests
    └── application.yaml         # Argo CD Application
```

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **OpenClaw Team**: For the excellent AI agent platform
- **Red Hat**: For OpenShift Container Platform
- **Kubernetes Community**: For Kustomize and ecosystem tools

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/ocp-openclaw/issues)
- **OpenClaw Docs**: https://docs.openclaw.ai
- **OpenShift Docs**: https://docs.openshift.com

---

## 🚦 Status

**Current Version**: 1.0.0
**OpenClaw Version**: 2026.3.7
**Tested on**: OpenShift 4.14, ROSA, ARO
**Status**: Production Ready ✅

---

**Made with ❤️ for the OpenShift community**
