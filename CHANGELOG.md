# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-03-31

### Fixed

- **ENOENT workspace error**: Fixed "Error: ENOENT: no such file or directory, mkdir '/home/node/.openclaw/workspace'" by using persistent volume instead of read-only ConfigMap mount
- **EROFS errors**: Resolved "read-only file system" errors when OpenClaw tried to write exec-approvals.json and other files
- Added initContainer to copy openclaw.json from ConfigMap to /data/.openclaw/ on startup
- Set HOME=/data environment variable to use writable persistent volume
- Configuration and device pairings now persist correctly across pod restarts

## [1.0.0] - 2026-03-31

### 🎉 Initial Release

Production-ready deployment of OpenClaw AI Agent on Red Hat OpenShift.

### Added

#### Core Deployment
- Complete OpenShift-native deployment manifests
- Kustomize overlays for lab and production environments
- Custom Security Context Constraints (SCC) for proper permissions
- RBAC configuration with least-privilege service account
- Persistent storage with PVC (40-100GB configurable)
- OpenShift Route with TLS edge termination

#### Architecture
- Nginx reverse proxy sidecar for external access
- Two-container pod architecture (openclaw + nginx-proxy)
- Init container for volume permissions
- Health probes for nginx container
- WebSocket support through nginx proxy

#### Configuration
- CORS configuration via `openclaw.json`
- Device pairing security for authentication
- Configurable allowed origins for Control UI
- Trusted proxy configuration for nginx
- Environment-specific resource limits

#### Security
- Non-root container execution
- Custom SCC with UID range 1000-65535
- fsGroup support for volume permissions
- All capabilities dropped
- Seccomp runtime/default profile
- Read-only root filesystem for nginx
- Device pairing for access control

#### Automation Scripts
- `install.sh` - Automated deployment (lab/production)
- `install-sidecar.sh` - Sidecar-specific deployment
- `validate.sh` - Health and configuration validation
- `uninstall.sh` - Clean removal with data preservation option
- `create-secrets.sh` - Interactive secret configuration
- `approve-devices.sh` - Device pairing approval helper
- `test-cors.sh` - CORS configuration testing
- `access-openclaw.sh` - Port-forward quick access

#### Documentation
- Comprehensive README.md with quick start
- DEPLOYMENT_SUCCESS.md - Success guide and verification
- CORS_FIXED.md - CORS configuration solution
- PAIRING.md - Device pairing guide
- SIDECAR_IMPLEMENTATION.md - Architecture details
- KNOWN_ISSUE_CORS.md - Historical troubleshooting
- Complete docs/ directory:
  - architecture.md
  - configuration.md
  - deployment.md
  - operations.md
  - prerequisites.md
  - security.md
  - troubleshooting.md

#### Operations
- Makefile with 30+ operational commands
- GitOps support with Argo CD application manifest
- Example configurations for lab and production
- Backup and restore procedures
- Health monitoring endpoints

### Fixed

- ✅ SCC seccomp profile configuration
- ✅ Health probes for localhost-bound application
- ✅ Nginx UID compatibility with OpenShift SCC
- ✅ CORS origin validation for Route access
- ✅ WebSocket connection through Route
- ✅ Device pairing authentication flow

### Technical Details

**Tested On:**
- Red Hat OpenShift 4.14 (AWS ROSA)
- OpenClaw version: 2026.3.7
- Nginx unprivileged: 1.25-alpine

**Architecture:**
```
External → Route (HTTPS) → Service → nginx:8080 → localhost:18789 → OpenClaw
```

**Resource Requirements:**
- Lab: 1 vCPU, 2Gi RAM, 40GB storage
- Production: 2-8 vCPU, 16Gi RAM, 100GB storage

**Key Features:**
- 2/2 containers running (openclaw + nginx-proxy)
- CORS properly configured
- Device pairing security active
- WebSocket connections working
- Persistent data storage
- Production-ready security hardening

### Known Issues

None at this time. All initial issues have been resolved.

### Migration Notes

This is the initial release. No migration needed.

---

## Release Process

Releases follow semantic versioning:

- **MAJOR** version for incompatible changes
- **MINOR** version for new functionality (backwards compatible)
- **PATCH** version for bug fixes (backwards compatible)

### Version History

- **1.0.0** (2026-03-31) - Initial production-ready release

---

For detailed changes in each file, see the [commit history](https://github.com/fklein82/ocp-openclaw/commits/main).
