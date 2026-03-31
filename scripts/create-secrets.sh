#!/usr/bin/env bash

set -euo pipefail

# OpenClaw Secrets Creation Script
# Usage: ./scripts/create-secrets.sh

###################
# Configuration
###################

NAMESPACE="openclaw"
SECRET_NAME="openclaw-secrets"

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

    # Check cluster connectivity
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi

    # Check if namespace exists
    if ! oc get namespace "${NAMESPACE}" &> /dev/null; then
        log_error "Namespace '${NAMESPACE}' does not exist. Please run install.sh first."
        exit 1
    fi

    log_success "Prerequisites validated"
}

generate_gateway_token() {
    # Generate a secure random token
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
    else
        # Fallback to /dev/urandom
        head -c 32 /dev/urandom | xxd -p -c 32
    fi
}

prompt_for_secrets() {
    echo ""
    echo "================================================"
    echo "OpenClaw Secret Configuration"
    echo "================================================"
    echo ""
    log_info "This script will help you configure API keys and tokens securely"
    echo ""

    # Gateway Token
    log_info "Gateway Token Configuration"
    echo "  The gateway token is used to authenticate requests to OpenClaw"
    echo ""

    read -p "Generate a random gateway token? (yes/no) [yes]: " -r GENERATE_TOKEN
    GENERATE_TOKEN="${GENERATE_TOKEN:-yes}"

    if [[ "${GENERATE_TOKEN}" =~ ^[Yy][Ee][Ss]$ ]]; then
        OPENCLAW_GATEWAY_TOKEN=$(generate_gateway_token)
        log_success "Generated secure gateway token"
    else
        read -sp "Enter gateway token (or press Enter to skip): " OPENCLAW_GATEWAY_TOKEN
        echo ""
    fi

    echo ""

    # AI Provider API Keys
    log_info "AI Provider API Keys Configuration"
    echo "  Configure API keys for AI providers (press Enter to skip any)"
    echo ""

    read -sp "Anthropic API Key (sk-ant-...): " ANTHROPIC_API_KEY
    echo ""

    read -sp "OpenAI API Key (sk-...): " OPENAI_API_KEY
    echo ""

    read -sp "OpenRouter API Key (sk-or-...): " OPENROUTER_API_KEY
    echo ""

    read -sp "Google API Key: " GOOGLE_API_KEY
    echo ""

    echo ""
}

create_secret() {
    log_info "Creating secret in namespace '${NAMESPACE}'..."

    # Build secret data
    local secret_args=()

    if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        secret_args+=("--from-literal=OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}")
    fi

    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        secret_args+=("--from-literal=ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
    fi

    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        secret_args+=("--from-literal=OPENAI_API_KEY=${OPENAI_API_KEY}")
    fi

    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        secret_args+=("--from-literal=OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
    fi

    if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
        secret_args+=("--from-literal=GOOGLE_API_KEY=${GOOGLE_API_KEY}")
    fi

    if [[ ${#secret_args[@]} -eq 0 ]]; then
        log_error "No secrets provided. Nothing to create."
        exit 1
    fi

    # Delete existing secret if it exists
    if oc get secret "${SECRET_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        log_warning "Secret '${SECRET_NAME}' already exists. Deleting..."
        oc delete secret "${SECRET_NAME}" -n "${NAMESPACE}"
    fi

    # Create new secret
    oc create secret generic "${SECRET_NAME}" \
        -n "${NAMESPACE}" \
        "${secret_args[@]}" \
        --dry-run=client -o yaml | \
        oc apply -f -

    log_success "Secret '${SECRET_NAME}' created successfully"
}

restart_deployment() {
    log_info "Restarting deployment to pick up new secrets..."

    if oc get deployment openclaw -n "${NAMESPACE}" &> /dev/null; then
        oc rollout restart deployment openclaw -n "${NAMESPACE}"
        log_success "Deployment restart initiated"

        log_info "Waiting for rollout to complete..."
        if oc rollout status deployment openclaw -n "${NAMESPACE}" --timeout=300s; then
            log_success "Rollout completed successfully"
        else
            log_warning "Rollout timed out or failed - check status with: oc rollout status deployment openclaw -n ${NAMESPACE}"
        fi
    else
        log_warning "Deployment not found - secrets will be used on next deployment"
    fi
}

display_summary() {
    echo ""
    echo "================================================"
    log_success "✓ Secrets configuration complete!"
    echo "================================================"
    echo ""

    log_info "Configured secrets:"

    # Count configured secrets
    if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        echo "  ✓ Gateway Token"
    fi

    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "  ✓ Anthropic API Key"
    fi

    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo "  ✓ OpenAI API Key"
    fi

    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        echo "  ✓ OpenRouter API Key"
    fi

    if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
        echo "  ✓ Google API Key"
    fi

    echo ""
    log_info "To view secret (base64 encoded):"
    echo "  oc get secret ${SECRET_NAME} -n ${NAMESPACE} -o yaml"
    echo ""

    log_info "To update secrets later:"
    echo "  ./scripts/create-secrets.sh"
    echo ""

    if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        log_warning "IMPORTANT: Save your gateway token securely!"
        echo "  Gateway Token: ${OPENCLAW_GATEWAY_TOKEN}"
        echo ""
    fi
}

###################
# Main Execution
###################

main() {
    echo "================================================"
    echo "OpenClaw Secrets Configuration"
    echo "================================================"
    echo ""

    check_prerequisites
    prompt_for_secrets
    create_secret
    restart_deployment
    display_summary
}

# Run main function
main "$@"
