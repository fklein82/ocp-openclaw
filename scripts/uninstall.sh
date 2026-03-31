#!/usr/bin/env bash

set -euo pipefail

# OpenClaw OpenShift Uninstallation Script
# Usage: ./scripts/uninstall.sh [--keep-data]

###################
# Configuration
###################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KEEP_DATA=false

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

parse_args() {
    for arg in "$@"; do
        case $arg in
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--keep-data]"
                echo ""
                echo "Options:"
                echo "  --keep-data    Keep PersistentVolumeClaim (preserves workspace data)"
                echo "  --help, -h     Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown argument: $arg"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if oc is installed
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
}

confirm_deletion() {
    echo ""
    log_warning "This will delete OpenClaw deployment from namespace 'openclaw'"

    if [[ "${KEEP_DATA}" == "false" ]]; then
        log_warning "PersistentVolumeClaim will be DELETED - all workspace data will be lost!"
    else
        log_info "PersistentVolumeClaim will be preserved (--keep-data flag)"
    fi

    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Uninstallation cancelled."
        exit 0
    fi
}

delete_deployment() {
    log_info "Deleting deployment..."

    if oc get deployment openclaw -n openclaw &> /dev/null; then
        oc delete deployment openclaw -n openclaw
        log_success "Deployment deleted"
    else
        log_warning "Deployment not found, skipping"
    fi
}

delete_service() {
    log_info "Deleting service..."

    if oc get service openclaw -n openclaw &> /dev/null; then
        oc delete service openclaw -n openclaw
        log_success "Service deleted"
    else
        log_warning "Service not found, skipping"
    fi
}

delete_route() {
    log_info "Deleting route..."

    if oc get route openclaw -n openclaw &> /dev/null; then
        oc delete route openclaw -n openclaw
        log_success "Route deleted"
    else
        log_warning "Route not found, skipping"
    fi
}

delete_configmap() {
    log_info "Deleting configmap..."

    # Delete all configmaps with openclaw label
    oc delete configmap -n openclaw -l app.kubernetes.io/name=openclaw 2>/dev/null || true
    log_success "ConfigMaps deleted"
}

delete_secrets() {
    log_info "Deleting secrets..."

    if oc get secret openclaw-secrets -n openclaw &> /dev/null; then
        oc delete secret openclaw-secrets -n openclaw
        log_success "Secrets deleted"
    else
        log_warning "Secrets not found, skipping"
    fi
}

delete_pvc() {
    if [[ "${KEEP_DATA}" == "true" ]]; then
        log_info "Keeping PersistentVolumeClaim (--keep-data flag)"
        return
    fi

    log_info "Deleting PersistentVolumeClaim..."

    if oc get pvc openclaw-data -n openclaw &> /dev/null; then
        oc delete pvc openclaw-data -n openclaw
        log_success "PVC deleted - workspace data removed"
    else
        log_warning "PVC not found, skipping"
    fi
}

delete_rbac() {
    log_info "Deleting RBAC resources..."

    # Delete RoleBinding
    oc delete rolebinding openclaw-rolebinding -n openclaw 2>/dev/null || true

    # Delete Role
    oc delete role openclaw-role -n openclaw 2>/dev/null || true

    # Delete ClusterRoleBinding
    oc delete clusterrolebinding openclaw-scc-binding 2>/dev/null || true

    # Delete ClusterRole
    oc delete clusterrole openclaw-scc-user 2>/dev/null || true

    log_success "RBAC resources deleted"
}

delete_serviceaccount() {
    log_info "Deleting service account..."

    if oc get serviceaccount openclaw -n openclaw &> /dev/null; then
        oc delete serviceaccount openclaw -n openclaw
        log_success "Service account deleted"
    else
        log_warning "Service account not found, skipping"
    fi
}

delete_scc() {
    log_info "Deleting Security Context Constraints..."

    # Check if running as cluster-admin
    if ! oc auth can-i delete securitycontextconstraints &> /dev/null; then
        log_warning "Insufficient permissions to delete SCC. Skipping (requires cluster-admin)."
        log_info "Ask your cluster administrator to run: oc delete scc openclaw-scc"
        return
    fi

    if oc get scc openclaw-scc &> /dev/null; then
        oc delete scc openclaw-scc
        log_success "SCC deleted"
    else
        log_warning "SCC not found, skipping"
    fi
}

delete_namespace() {
    log_info "Deleting namespace..."

    read -p "Delete entire namespace 'openclaw'? (yes/no): " -r
    echo ""

    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        if oc get namespace openclaw &> /dev/null; then
            oc delete namespace openclaw
            log_success "Namespace 'openclaw' deleted"
        else
            log_warning "Namespace not found, skipping"
        fi
    else
        log_info "Namespace preserved"
    fi
}

###################
# Main Execution
###################

main() {
    echo "================================================"
    echo "OpenClaw OpenShift Uninstallation"
    echo "================================================"
    echo ""

    parse_args "$@"
    check_prerequisites
    confirm_deletion

    echo ""
    log_info "Starting uninstallation..."
    echo ""

    delete_deployment
    delete_service
    delete_route
    delete_configmap
    delete_secrets
    delete_pvc
    delete_rbac
    delete_serviceaccount
    delete_scc
    delete_namespace

    echo ""
    log_success "✓ OpenClaw uninstallation complete!"

    if [[ "${KEEP_DATA}" == "true" ]]; then
        echo ""
        log_info "PVC 'openclaw-data' was preserved. To delete manually:"
        echo "  oc delete pvc openclaw-data -n openclaw"
    fi

    echo ""
}

# Run main function
main "$@"
