#!/usr/bin/env bash

set -euo pipefail

# OpenClaw OpenShift Validation Script
# Usage: ./scripts/validate.sh

###################
# Configuration
###################

NAMESPACE="openclaw"
DEPLOYMENT_NAME="openclaw"
SERVICE_NAME="openclaw"
ROUTE_NAME="openclaw"

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
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

VALIDATION_FAILED=false

mark_failed() {
    VALIDATION_FAILED=true
}

###################
# Validation Functions
###################

check_cluster_connection() {
    log_info "Checking cluster connection..."

    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster"
        mark_failed
        return 1
    fi

    local user=$(oc whoami)
    local server=$(oc whoami --show-server)
    log_success "Connected to ${server} as ${user}"
}

check_namespace() {
    log_info "Checking namespace..."

    if ! oc get namespace "${NAMESPACE}" &> /dev/null; then
        log_error "Namespace '${NAMESPACE}' does not exist"
        mark_failed
        return 1
    fi

    log_success "Namespace '${NAMESPACE}' exists"
}

check_serviceaccount() {
    log_info "Checking service account..."

    if ! oc get serviceaccount openclaw -n "${NAMESPACE}" &> /dev/null; then
        log_error "Service account 'openclaw' not found in namespace '${NAMESPACE}'"
        mark_failed
        return 1
    fi

    log_success "Service account 'openclaw' exists"
}

check_scc() {
    log_info "Checking Security Context Constraints..."

    if ! oc get scc openclaw-scc &> /dev/null; then
        log_warning "SCC 'openclaw-scc' not found (may require cluster-admin)"
        return 0
    fi

    log_success "SCC 'openclaw-scc' exists"

    # Check if service account can use the SCC
    local can_use=$(oc auth can-i use scc/openclaw-scc --as=system:serviceaccount:${NAMESPACE}:openclaw 2>/dev/null && echo "yes" || echo "no")

    if [[ "${can_use}" == "yes" ]]; then
        log_success "Service account can use SCC 'openclaw-scc'"
    else
        log_warning "Service account may not have permission to use SCC"
    fi
}

check_rbac() {
    log_info "Checking RBAC..."

    if ! oc get role openclaw-role -n "${NAMESPACE}" &> /dev/null; then
        log_error "Role 'openclaw-role' not found"
        mark_failed
        return 1
    fi

    if ! oc get rolebinding openclaw-rolebinding -n "${NAMESPACE}" &> /dev/null; then
        log_error "RoleBinding 'openclaw-rolebinding' not found"
        mark_failed
        return 1
    fi

    log_success "RBAC resources configured"
}

check_configmap() {
    log_info "Checking ConfigMap..."

    if ! oc get configmap -n "${NAMESPACE}" -l app.kubernetes.io/name=openclaw &> /dev/null; then
        log_error "ConfigMap not found"
        mark_failed
        return 1
    fi

    log_success "ConfigMap exists"
}

check_secret() {
    log_info "Checking Secret..."

    if ! oc get secret openclaw-secrets -n "${NAMESPACE}" &> /dev/null; then
        log_error "Secret 'openclaw-secrets' not found"
        mark_failed
        return 1
    fi

    log_success "Secret 'openclaw-secrets' exists"

    # Check if default token is still in use
    local gateway_token=$(oc get secret openclaw-secrets -n "${NAMESPACE}" -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [[ "${gateway_token}" == "CHANGE_ME_IN_PRODUCTION" ]]; then
        log_warning "Gateway token is still set to default value - update for production!"
    fi
}

check_pvc() {
    log_info "Checking PersistentVolumeClaim..."

    if ! oc get pvc openclaw-data -n "${NAMESPACE}" &> /dev/null; then
        log_error "PVC 'openclaw-data' not found"
        mark_failed
        return 1
    fi

    local status=$(oc get pvc openclaw-data -n "${NAMESPACE}" -o jsonpath='{.status.phase}')

    if [[ "${status}" == "Bound" ]]; then
        log_success "PVC 'openclaw-data' is Bound"
    else
        log_error "PVC 'openclaw-data' status: ${status} (expected: Bound)"
        mark_failed
    fi

    # Show storage details
    local size=$(oc get pvc openclaw-data -n "${NAMESPACE}" -o jsonpath='{.spec.resources.requests.storage}')
    local sc=$(oc get pvc openclaw-data -n "${NAMESPACE}" -o jsonpath='{.spec.storageClassName}')
    log_info "  Storage: ${size}, StorageClass: ${sc:-<default>}"
}

check_deployment() {
    log_info "Checking Deployment..."

    if ! oc get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        log_error "Deployment '${DEPLOYMENT_NAME}' not found"
        mark_failed
        return 1
    fi

    local desired=$(oc get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
    local ready=$(oc get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local available=$(oc get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")

    if [[ "${ready}" == "${desired}" ]] && [[ "${available}" == "${desired}" ]]; then
        log_success "Deployment is ready (${ready}/${desired} replicas)"
    else
        log_error "Deployment not ready (Ready: ${ready}/${desired}, Available: ${available}/${desired})"
        mark_failed
    fi
}

check_pods() {
    log_info "Checking Pods..."

    local pod_count=$(oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=openclaw --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${pod_count}" -gt 0 ]]; then
        log_success "${pod_count} pod(s) running"

        # Get pod details
        local pod_name=$(oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

        if [[ -n "${pod_name}" ]]; then
            # Check pod readiness
            local ready=$(oc get pod "${pod_name}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

            if [[ "${ready}" == "True" ]]; then
                log_success "Pod '${pod_name}' is Ready"
            else
                log_warning "Pod '${pod_name}' not ready yet"
            fi

            # Check for restarts
            local restarts=$(oc get pod "${pod_name}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

            if [[ "${restarts}" -gt 0 ]]; then
                log_warning "Pod has restarted ${restarts} time(s) - check logs"
            fi
        fi
    else
        log_error "No running pods found"
        mark_failed

        # Show pod status
        log_info "Current pod status:"
        oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=openclaw 2>/dev/null || echo "  No pods found"
    fi
}

check_service() {
    log_info "Checking Service..."

    if ! oc get service "${SERVICE_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        log_error "Service '${SERVICE_NAME}' not found"
        mark_failed
        return 1
    fi

    local endpoints=$(oc get endpoints "${SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)

    if [[ -n "${endpoints}" ]]; then
        log_success "Service '${SERVICE_NAME}' has endpoints: ${endpoints}"
    else
        log_warning "Service '${SERVICE_NAME}' has no endpoints (pods may not be ready)"
    fi
}

check_route() {
    log_info "Checking Route..."

    if ! oc get route "${ROUTE_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        log_error "Route '${ROUTE_NAME}' not found"
        mark_failed
        return 1
    fi

    local host=$(oc get route "${ROUTE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.host}')
    local tls=$(oc get route "${ROUTE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.tls.termination}')

    log_success "Route exists: https://${host}"
    log_info "  TLS termination: ${tls:-none}"
}

check_endpoint_health() {
    log_info "Checking endpoint health..."

    local route_host=$(oc get route "${ROUTE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)

    if [[ -z "${route_host}" ]]; then
        log_warning "Cannot check endpoint health - route not found"
        return 0
    fi

    # Check healthz endpoint
    local health_url="https://${route_host}/healthz"

    log_info "Testing health endpoint: ${health_url}"

    if command -v curl &> /dev/null; then
        local http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "${health_url}" 2>/dev/null || echo "000")

        if [[ "${http_code}" == "200" ]]; then
            log_success "Health check passed (HTTP ${http_code})"
        else
            log_warning "Health check returned HTTP ${http_code} (may still be starting)"
        fi
    else
        log_warning "curl not available - skipping health check"
    fi
}

check_events() {
    log_info "Checking recent events..."

    local error_count=$(oc get events -n "${NAMESPACE}" --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')

    if [[ "${error_count}" -gt 0 ]]; then
        log_warning "Found ${error_count} warning event(s) in namespace"
        log_info "To view: oc get events -n ${NAMESPACE} --field-selector type=Warning --sort-by='.lastTimestamp'"
    else
        log_success "No warning events found"
    fi
}

###################
# Main Execution
###################

main() {
    echo "================================================"
    echo "OpenClaw OpenShift Validation"
    echo "================================================"
    echo ""

    check_cluster_connection
    echo ""

    check_namespace
    check_serviceaccount
    check_scc
    check_rbac
    echo ""

    check_configmap
    check_secret
    check_pvc
    echo ""

    check_deployment
    check_pods
    echo ""

    check_service
    check_route
    echo ""

    check_endpoint_health
    echo ""

    check_events
    echo ""

    echo "================================================"

    if [[ "${VALIDATION_FAILED}" == "true" ]]; then
        log_error "Validation FAILED - see errors above"
        echo ""
        echo "Troubleshooting commands:"
        echo "  oc get pods -n ${NAMESPACE}"
        echo "  oc describe pod -n ${NAMESPACE} -l app.kubernetes.io/name=openclaw"
        echo "  oc logs -n ${NAMESPACE} -l app.kubernetes.io/name=openclaw --tail=100"
        echo "  oc get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
        echo ""
        exit 1
    else
        log_success "✓ All validations passed!"
        echo ""
        echo "OpenClaw is healthy and ready to use"
        echo ""

        local route_host=$(oc get route "${ROUTE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)
        if [[ -n "${route_host}" ]]; then
            echo "Access OpenClaw at: https://${route_host}"
        fi
        echo ""
        exit 0
    fi
}

# Run main function
main "$@"
