#!/usr/bin/env bash
#
# Test CORS Configuration for OpenClaw
#
# This script verifies that the CORS configuration is properly set up
# and the OpenClaw Control UI is accessible via the OpenShift Route.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

# Configuration
NAMESPACE="${NAMESPACE:-openclaw}"
DEPLOYMENT_NAME="openclaw"

log_info "Testing CORS Configuration for OpenClaw..."
echo ""

# Test 1: Check pod is running
log_info "Test 1: Checking pod status..."
POD_STATUS=$(oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${POD_STATUS}" == "Running" ]]; then
    POD_READY=$(oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="openclaw")].ready}')
    if [[ "${POD_READY}" == "true" ]]; then
        log_success "Pod is Running and Ready"
    else
        log_error "Pod is Running but not Ready"
        exit 1
    fi
else
    log_error "Pod is not Running (status: ${POD_STATUS})"
    exit 1
fi

# Test 2: Check openclaw.json configuration is mounted
log_info "Test 2: Checking openclaw.json configuration..."
CONFIG_CONTENT=$(oc exec -n "${NAMESPACE}" deployment/"${DEPLOYMENT_NAME}" -c openclaw -- cat /home/node/.openclaw/openclaw.json 2>/dev/null || echo "")
if [[ -n "${CONFIG_CONTENT}" ]]; then
    log_success "Configuration file is mounted"

    # Check for allowedOrigins
    if echo "${CONFIG_CONTENT}" | grep -q "allowedOrigins"; then
        log_success "allowedOrigins is configured"

        # Get Route URL
        ROUTE_HOST=$(oc get route openclaw -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
        if [[ -n "${ROUTE_HOST}" ]]; then
            if echo "${CONFIG_CONTENT}" | grep -q "${ROUTE_HOST}"; then
                log_success "Route URL is in allowedOrigins list"
            else
                log_warning "Route URL might not be in allowedOrigins list"
            fi
        fi
    else
        log_error "allowedOrigins is NOT configured"
        exit 1
    fi

    # Check for auth token
    if echo "${CONFIG_CONTENT}" | grep -q '"auth"'; then
        log_success "Authentication is configured"
    else
        log_warning "Authentication might not be configured"
    fi
else
    log_error "Configuration file is NOT mounted"
    exit 1
fi

# Test 3: Check logs for CORS errors
log_info "Test 3: Checking logs for CORS errors..."
RECENT_LOGS=$(oc logs -n "${NAMESPACE}" deployment/"${DEPLOYMENT_NAME}" -c openclaw --tail=50 2>/dev/null || echo "")
if echo "${RECENT_LOGS}" | grep -q "origin not allowed"; then
    log_error "CORS errors found in logs!"
    echo "${RECENT_LOGS}" | grep "origin not allowed"
    exit 1
else
    log_success "No CORS errors in recent logs"
fi

# Test 4: Check Route accessibility
log_info "Test 4: Testing Route accessibility..."
ROUTE_URL=$(oc get route openclaw -n "${NAMESPACE}" -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "")
if [[ -n "${ROUTE_URL}" ]]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${ROUTE_URL}" 2>/dev/null || echo "000")
    if [[ "${HTTP_STATUS}" == "200" ]]; then
        log_success "Route is accessible (HTTP ${HTTP_STATUS})"
    else
        log_error "Route returned HTTP ${HTTP_STATUS}"
        exit 1
    fi
else
    log_error "Route not found"
    exit 1
fi

# Test 5: Get token and display access URL
log_info "Test 5: Getting access token..."
TOKEN=$(oc get secret openclaw-secrets -n "${NAMESPACE}" -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
if [[ -n "${TOKEN}" ]]; then
    log_success "Token retrieved from secret"
else
    log_warning "Could not retrieve token from secret"
    TOKEN="CHANGE_ME_IN_PRODUCTION"
fi

# Final summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "All CORS tests passed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}✓ OpenClaw is ready to use${NC}"
echo ""
echo "Access OpenClaw at:"
echo -e "${BLUE}${ROUTE_URL}/#token=${TOKEN}${NC}"
echo ""
echo "Or copy this full URL:"
echo "${ROUTE_URL}/#token=${TOKEN}"
echo ""

# Open in browser (optional)
if [[ "${OPEN_BROWSER:-false}" == "true" ]]; then
    log_info "Opening in browser..."
    if command -v open &> /dev/null; then
        open "${ROUTE_URL}/#token=${TOKEN}"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "${ROUTE_URL}/#token=${TOKEN}"
    else
        log_warning "Could not detect browser command (open/xdg-open)"
    fi
fi

echo ""
log_info "For more details, see CORS_FIXED.md"
echo ""
