#!/usr/bin/env bash
#
# Approve OpenClaw Device Pairing Requests
#
# This script helps you approve pending device pairing requests
# for the OpenClaw Control UI.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}  OpenClaw Device Pairing Approval Tool${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if deployment exists
if ! oc get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    log_error "OpenClaw deployment not found in namespace '${NAMESPACE}'"
    exit 1
fi

# List pending pairing requests
log_info "Fetching pending pairing requests..."
echo ""

DEVICES_OUTPUT=$(oc exec -n "${NAMESPACE}" deployment/"${DEPLOYMENT_NAME}" -c openclaw -- \
  openclaw devices list 2>&1)

echo "${DEVICES_OUTPUT}"
echo ""

# Extract pending request IDs (simple approach)
# Look for lines with UUID format in the table
PENDING_IDS=$(echo "${DEVICES_OUTPUT}" | \
  grep -E '│ [a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | \
  awk -F '│' '{print $2}' | \
  tr -d ' ' | \
  grep -E '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' || true)

if [ -z "${PENDING_IDS}" ]; then
    log_info "No pending pairing requests."
    echo ""
    log_info "To see paired devices, run:"
    echo "  oc exec -n ${NAMESPACE} deployment/${DEPLOYMENT_NAME} -c openclaw -- openclaw devices list"
    echo ""
    exit 0
fi

# Count pending requests
PENDING_COUNT=$(echo "${PENDING_IDS}" | wc -l | tr -d ' ')
log_warning "Found ${PENDING_COUNT} pending pairing request(s)"
echo ""

# Interactive approval
if [ "${AUTO_APPROVE:-false}" == "true" ]; then
    CONFIRM="y"
else
    echo -e "${YELLOW}⚠️  Review the IP addresses and device information above${NC}"
    echo -e "${YELLOW}   Only approve devices you recognize!${NC}"
    echo ""
    read -p "Approve ALL pending requests? (y/N): " CONFIRM
fi

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    log_info "Cancelled. No devices were approved."
    echo ""
    log_info "To manually approve a specific device:"
    echo "  oc exec -n ${NAMESPACE} deployment/${DEPLOYMENT_NAME} -c openclaw -- \\"
    echo "    openclaw devices approve <REQUEST_ID>"
    echo ""
    exit 0
fi

echo ""
log_info "Approving devices..."
echo ""

# Approve each pending request
APPROVED_COUNT=0
FAILED_COUNT=0

while IFS= read -r REQUEST_ID; do
    if [ -z "${REQUEST_ID}" ]; then
        continue
    fi

    echo -e "${CYAN}→${NC} Approving ${REQUEST_ID}..."

    if oc exec -n "${NAMESPACE}" deployment/"${DEPLOYMENT_NAME}" -c openclaw -- \
       openclaw devices approve "${REQUEST_ID}" 2>&1 | grep -q "Approved"; then
        log_success "Approved"
        APPROVED_COUNT=$((APPROVED_COUNT + 1))
    else
        log_error "Failed to approve ${REQUEST_ID}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done <<< "${PENDING_IDS}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "${APPROVED_COUNT}" -gt 0 ]; then
    log_success "Successfully approved ${APPROVED_COUNT} device(s)"
    echo ""
    echo -e "${GREEN}✓ Refresh your browser to connect to OpenClaw!${NC}"
    echo ""
    ROUTE_URL=$(oc get route openclaw -n "${NAMESPACE}" -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "")
    if [ -n "${ROUTE_URL}" ]; then
        echo "Access OpenClaw at:"
        echo -e "${BLUE}${ROUTE_URL}${NC}"
    fi
else
    log_warning "No devices were approved"
fi

if [ "${FAILED_COUNT}" -gt 0 ]; then
    log_warning "${FAILED_COUNT} device(s) failed to approve"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show paired devices
log_info "Currently paired devices:"
echo ""
oc exec -n "${NAMESPACE}" deployment/"${DEPLOYMENT_NAME}" -c openclaw -- \
  openclaw devices list 2>&1 | grep -A 100 "Paired" || log_info "Run devices list to see paired devices"

echo ""
log_info "For more information, see PAIRING.md"
echo ""
