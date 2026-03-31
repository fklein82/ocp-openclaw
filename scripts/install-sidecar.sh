#!/usr/bin/env bash

set -euo pipefail

# OpenClaw OpenShift Installation Script (with Nginx Sidecar)
# Usage: ./scripts/install-sidecar.sh

###################
# Configuration
###################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFESTS_DIR="${PROJECT_ROOT}/manifests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###################
# Helper Functions
###################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

###################
# Main Execution
###################

main() {
    echo "================================================"
    echo "OpenClaw OpenShift Deployment (with Nginx Sidecar)"
    echo "================================================"
    echo ""

    log_info "This deployment includes an nginx reverse proxy sidecar"
    log_info "This allows external Route access to OpenClaw"
    echo ""

    # Check if oc is available
    if ! command -v oc &> /dev/null; then
        log_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi

    # Check cluster connectivity
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi

    log_success "Logged in as: $(oc whoami)"
    log_info "Target cluster: $(oc whoami --show-server)"
    echo ""

    # Create namespace if it doesn't exist
    if ! oc get namespace openclaw &> /dev/null; then
        log_info "Creating namespace 'openclaw'..."
        oc create namespace openclaw
        log_success "Namespace 'openclaw' created"
    else
        log_warning "Namespace 'openclaw' already exists"
    fi

    # Apply SCC
    log_info "Applying Security Context Constraints..."
    if oc auth can-i create securitycontextconstraints &> /dev/null; then
        oc apply -f "${MANIFESTS_DIR}/base/scc.yaml"
        log_success "SCC 'openclaw-scc' applied"
    else
        log_error "Insufficient permissions to create SCC. Need cluster-admin role."
        log_error "Please ask your cluster administrator to apply: ${MANIFESTS_DIR}/base/scc.yaml"
        exit 1
    fi

    # Deploy with sidecar
    log_info "Deploying OpenClaw with nginx sidecar..."
    oc apply -k "${MANIFESTS_DIR}/sidecar"
    log_success "Manifests applied successfully"

    echo ""
    log_info "Waiting for deployment to be ready..."

    # Wait for deployment
    local timeout=300
    local start_time=$(date +%s)

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ ${elapsed} -gt ${timeout} ]]; then
            log_error "Timeout waiting for deployment."
            log_info "Check status with: oc get pods -n openclaw"
            exit 1
        fi

        local ready=$(oc get deployment openclaw -n openclaw -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(oc get deployment openclaw -n openclaw -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

        if [[ "${ready}" == "${desired}" ]] && [[ "${ready}" != "0" ]]; then
            log_success "Deployment is ready (${ready}/${desired} replicas)"
            break
        fi

        log_info "Waiting for deployment... (${ready}/${desired} replicas ready, ${elapsed}s elapsed)"
        sleep 10
    done

    echo ""
    log_success "✓ OpenClaw deployed successfully with nginx sidecar!"
    echo ""

    # Display access info
    log_info "Retrieving access information..."
    local route_url=$(oc get route openclaw -n openclaw -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

    if [[ -n "${route_url}" ]]; then
        echo ""
        echo "================================================"
        log_success "OpenClaw is accessible via Route!"
        echo ""
        echo "  🌐 External URL: https://${route_url}"
        echo ""
        echo "  Test with: curl -I https://${route_url}"
        echo "================================================"
    fi

    echo ""
    log_info "Useful commands:"
    echo "  - View pods:        oc get pods -n openclaw"
    echo "  - View logs:        oc logs -f deployment/openclaw -n openclaw -c openclaw"
    echo "  - View nginx logs:  oc logs -f deployment/openclaw -n openclaw -c nginx-proxy"
    echo "  - View events:      oc get events -n openclaw --sort-by='.lastTimestamp'"
    echo ""

    log_success "Installation complete!"
}

# Run main function
main "$@"
