# Prerequisites

This document outlines all prerequisites for deploying OpenClaw on Red Hat OpenShift.

## Table of Contents

- [Cluster Requirements](#cluster-requirements)
- [CLI Tools](#cli-tools)
- [Permissions](#permissions)
- [Storage](#storage)
- [Network](#network)
- [AI Provider API Keys](#ai-provider-api-keys)
- [Knowledge Requirements](#knowledge-requirements)

---

## Cluster Requirements

### OpenShift Version

- **Minimum**: OpenShift 4.10+
- **Recommended**: OpenShift 4.12+ or later
- **Tested on**: OpenShift 4.14

### Cluster Resources

The cluster must have sufficient resources available:

| Resource | Lab Environment | Production Environment |
|----------|----------------|------------------------|
| CPU      | 2 vCPU         | 8 vCPU                |
| Memory   | 4 GB           | 16 GB                 |
| Storage  | 20 GB          | 100 GB                |

### Cluster Type

Compatible with all OpenShift deployment types:
- Red Hat OpenShift Container Platform (OCP)
- Red Hat OpenShift Dedicated (OSD)
- Red Hat OpenShift on AWS (ROSA)
- Azure Red Hat OpenShift (ARO)
- OpenShift Sandbox (for testing only)

---

## CLI Tools

### Required

#### OpenShift CLI (oc)

```bash
# Check if installed
oc version

# Installation (macOS)
brew install openshift-cli

# Installation (Linux)
# Download from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
tar -xvf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Installation (Windows)
# Download from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
```

**Minimum version**: 4.10+

### Optional but Recommended

#### kubectl

```bash
# Usually included with oc, but can be installed separately
kubectl version --client
```

#### kustomize

```bash
# Check if installed
kustomize version

# Installation (macOS)
brew install kustomize

# Installation (Linux)
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/
```

**Note**: `oc` has built-in kustomize support via `oc apply -k`, so standalone kustomize is optional.

#### jq (for JSON processing)

```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RHEL/CentOS
```

---

## Permissions

### Required Permissions

You need the following permissions to deploy OpenClaw:

#### Namespace-Level Permissions

- Create and manage resources in the target namespace:
  - Deployments
  - Services
  - Routes
  - ConfigMaps
  - Secrets
  - PersistentVolumeClaims
  - ServiceAccounts
  - Roles
  - RoleBindings

#### Cluster-Level Permissions (for SCC)

- **SecurityContextConstraints**: `create`, `update`, `delete`, `use`
- **ClusterRole**: `create`, `update`, `delete`
- **ClusterRoleBinding**: `create`, `update`, `delete`

**Note**: These typically require `cluster-admin` role. If you don't have cluster-admin access, ask your OpenShift administrator to apply the SCC for you.

### Verify Permissions

```bash
# Check if you can create namespaces
oc auth can-i create namespace

# Check if you can create SCC (cluster-admin required)
oc auth can-i create securitycontextconstraints

# Check current user
oc whoami

# List accessible projects
oc projects
```

---

## Storage

### Storage Class

The cluster must have at least one StorageClass available:

```bash
# List available storage classes
oc get storageclass

# Check default storage class
oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

### Storage Requirements

| Environment | Minimum Size | Recommended Size | Access Mode |
|-------------|-------------|------------------|-------------|
| Lab         | 20 GB       | 40 GB           | RWO         |
| Production  | 80 GB       | 100 GB          | RWO         |

**Access Modes Explained**:
- **RWO** (ReadWriteOnce): Volume can be mounted as read-write by a single node
  - ✅ Sufficient for single-replica deployments
  - ✅ Most common in block storage (AWS EBS, Azure Disk, etc.)

- **RWX** (ReadWriteMany): Required only for multi-replica deployments
  - ⚠️ Not needed for OpenClaw default deployment (single replica)
  - Requires NFS, CephFS, or similar shared filesystem

### Common Storage Classes by Platform

| Platform | Default StorageClass | Type |
|----------|---------------------|------|
| AWS ROSA | `gp3-csi` or `gp2` | AWS EBS |
| Azure ARO | `managed-premium` | Azure Disk |
| OpenShift Dedicated | `gp2` or `gp3-csi` | AWS EBS |
| On-Premises | Varies | Often Ceph RBD, NFS |

---

## Network

### Ingress / Routes

OpenShift uses Routes (not Kubernetes Ingress) for external access:

- Default router must be available
- Route admission should allow the target namespace
- TLS certificates (optional but recommended)

### Firewall / Security Groups

If deploying on a cloud platform, ensure:

- OpenShift router has external access (typically port 443)
- No firewall rules blocking the route domain

### External Access

The deployment creates a Route with:
- **Protocol**: HTTPS (TLS edge termination)
- **Port**: 443 → Service 18789

---

## AI Provider API Keys

OpenClaw requires at least **one** AI provider API key to function.

### Supported Providers

| Provider | API Key Format | Get Your Key |
|----------|---------------|--------------|
| **Anthropic** (Claude) | `sk-ant-...` | https://console.anthropic.com/ |
| **OpenAI** (GPT) | `sk-...` | https://platform.openai.com/api-keys |
| **OpenRouter** | `sk-or-...` | https://openrouter.ai/keys |
| **Google AI** (Gemini) | Various | https://makersuite.google.com/app/apikey |

### Obtaining API Keys

#### Anthropic (Recommended)

1. Go to https://console.anthropic.com/
2. Sign up or log in
3. Navigate to **API Keys**
4. Click **Create Key**
5. Copy the key (starts with `sk-ant-`)

#### OpenAI

1. Go to https://platform.openai.com/
2. Sign up or log in
3. Navigate to **API Keys**
4. Click **Create new secret key**
5. Copy the key (starts with `sk-`)

### Cost Considerations

- API keys are **pay-per-use**
- Set up billing limits in provider console
- Monitor usage regularly
- Consider using multiple providers for redundancy

---

## Knowledge Requirements

### Required Knowledge

- Basic OpenShift/Kubernetes concepts:
  - Pods, Deployments, Services
  - Namespaces/Projects
  - ConfigMaps and Secrets
  - PersistentVolumeClaims
- OpenShift-specific concepts:
  - Routes (vs Kubernetes Ingress)
  - Security Context Constraints (SCC)
- Command-line proficiency with `oc` CLI
- Basic bash scripting (for installation scripts)

### Recommended Knowledge

- Kustomize for manifest management
- YAML syntax and structure
- Troubleshooting Kubernetes/OpenShift workloads
- Git for version control

---

## Pre-Deployment Checklist

Before deploying OpenClaw, verify:

- [ ] OpenShift cluster is accessible and healthy
- [ ] `oc` CLI is installed and configured
- [ ] You are logged in to the cluster (`oc whoami`)
- [ ] You have cluster-admin or sufficient permissions
- [ ] At least one StorageClass is available
- [ ] Default storage class is configured (or you know which to use)
- [ ] You have at least one AI provider API key
- [ ] Network allows external route access
- [ ] You have reviewed resource requirements

---

## Next Steps

Once all prerequisites are met, proceed to:

➡️ [Deployment Guide](deployment.md)

---

## References

- [OpenShift Documentation](https://docs.openshift.com/)
- [OpenClaw Official Docs](https://docs.openclaw.ai/)
- [Kustomize Documentation](https://kustomize.io/)
