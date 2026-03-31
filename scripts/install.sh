#!/usr/bin/env bash

set -euo pipefail

# OpenClaw OpenShift Installation Script
# Usage: ./scripts/install.sh [lab|production]

###################
# Configuration
###################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFESTS_DIR="${PROJECT_ROOT}/manifests"

# Default to lab if no argument provided
ENVIRONMENT="${1:-lab}"

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

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if oc is installed
    if ! command -v oc &> /dev/null; then
        log_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi
    log_success "oc CLI found: $(oc version --client -o json | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4 || echo 'unknown')"

    # Check if kubectl is installed (optional but useful)
    if command -v kubectl &> /dev/null; then
        log_info "kubectl found: $(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4 || echo 'unknown')"
    fi

    # Check if kustomize is available
    if ! command -v kustomize &> /dev/null; then
        log_warning "kustomize not found. Using oc's built-in kustomize support."
    else
        log_success "kustomize found: $(kustomize version --short 2>/dev/null || kustomize version 2>/dev/null | head -n1)"
    fi

    # Check cluster connectivity
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi
    log_success "Logged in as: $(oc whoami)"

    # Check cluster access
    if ! oc auth can-i create namespace &> /dev/null; then
        log_error "Insufficient permissions. Need cluster-admin or namespace creation privileges."
        exit 1
    fi
    log_success "Cluster permissions validated"

    # Display cluster info
    CLUSTER_URL=$(oc whoami --show-server)
    log_info "Target cluster: ${CLUSTER_URL}"
}

validate_environment() {
    if [[ "${ENVIRONMENT}" != "lab" && "${ENVIRONMENT}" != "production" ]]; then
        log_error "Invalid environment: ${ENVIRONMENT}"
        log_info "Usage: $0 [lab|production]"
        exit 1
    fi
    log_info "Deployment environment: ${ENVIRONMENT}"
}

check_storage_class() {
    log_info "Checking available storage classes..."

    if ! oc get storageclass &> /dev/null; then
        log_warning "Cannot list storage classes. Continuing anyway..."
        return
    fi

    local default_sc=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "${default_sc}" ]]; then
        log_success "Default storage class: ${default_sc}"
    else
        log_warning "No default storage class found. You may need to specify one manually."
        log_info "Available storage classes:"
        oc get storageclass -o name 2>/dev/null || true
    fi
}

create_namespace() {
    log_info "Creating namespace 'openclaw'..."

    if oc get namespace openclaw &> /dev/null; then
        log_warning "Namespace 'openclaw' already exists. Skipping creation."
    else
        oc create namespace openclaw
        log_success "Namespace 'openclaw' created"
    fi
}

apply_scc() {
    log_info "Applying Security Context Constraints..."

    # Check if running as cluster-admin
    if ! oc auth can-i create securitycontextconstraints &> /dev/null; then
        log_error "Insufficient permissions to create SCC. Need cluster-admin role."
        log_error "Please ask your cluster administrator to apply: ${MANIFESTS_DIR}/base/scc.yaml"
        exit 1
    fi

    oc apply -f "${MANIFESTS_DIR}/base/scc.yaml"
    log_success "SCC 'openclaw-scc' applied"
}

deploy_manifests() {
    log_info "Deploying OpenClaw manifests for environment: ${ENVIRONMENT}..."

    local overlay_dir="${MANIFESTS_DIR}/${ENVIRONMENT}"

    if [[ ! -d "${overlay_dir}" ]]; then
        log_error "Overlay directory not found: ${overlay_dir}"
        exit 1
    fi

    # Apply manifests using oc with kustomize
    oc apply -k "${overlay_dir}"

    log_success "Manifests applied successfully"
}

wait_for_deployment() {
    log_info "Waiting for deployment to be ready..."

    local timeout=300  # 5 minutes
    local start_time=$(date +%s)

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ ${elapsed} -gt ${timeout} ]]; then
            log_error "Timeout waiting for deployment. Check status with: oc get pods -n openclaw"
            exit 1
        fi

        # Check if deployment is ready
        local ready=$(oc get deployment openclaw -n openclaw -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(oc get deployment openclaw -n openclaw -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

        if [[ "${ready}" == "${desired}" ]] && [[ "${ready}" != "0" ]]; then
            log_success "Deployment is ready (${ready}/${desired} replicas)"
            break
        fi

        log_info "Waiting for deployment... (${ready}/${desired} replicas ready, ${elapsed}s elapsed)"
        sleep 10
    done
}

display_access_info() {
    log_info "Retrieving access information..."

    # Get route URL
    local route_url=$(oc get route openclaw -n openclaw -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

    if [[ -n "${route_url}" ]]; then
        log_success "OpenClaw Gateway URL: https://${route_url}"
        log_info "Health check: https://${route_url}/healthz"
    else
        log_warning "Route not found. Check manually with: oc get route -n openclaw"
    fi

    # Display useful commands
    echo ""
    echo "================================================"
    log_info "Useful commands:"
    echo "  - View pods:        oc get pods -n openclaw"
    echo "  - View logs:        oc logs -f deployment/openclaw -n openclaw"
    echo "  - View events:      oc get events -n openclaw --sort-by='.lastTimestamp'"
    echo "  - Port forward:     oc port-forward -n openclaw svc/openclaw 18789:18789"
    echo "  - Shell access:     oc exec -it -n openclaw deployment/openclaw -- /bin/sh"
    echo "================================================"
}

check_secrets() {
    log_warning "IMPORTANT: Don't forget to update secrets with actual API keys!"
    log_info "Run: ./scripts/create-secrets.sh to set API keys securely"
}

###################
# Main Execution
###################

main() {
    echo "================================================"
    echo "OpenClaw OpenShift Deployment"
    echo "================================================"
    echo ""

    validate_environment
    check_prerequisites
    check_storage_class

    echo ""
    log_info "Starting deployment..."
    echo ""

    create_namespace
    apply_scc
    deploy_manifests
    wait_for_deployment

    echo ""
    log_success "✓ OpenClaw deployed successfully!"
    echo ""

    display_access_info
    check_secrets

    echo ""
    log_success "Installation complete!"
}

# Run main function
main "$@"
