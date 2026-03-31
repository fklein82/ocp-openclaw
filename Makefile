.PHONY: help install uninstall validate clean logs shell port-forward status test-connection deploy-lab deploy-prod secrets

# Default environment
ENV ?= lab
NAMESPACE ?= openclaw

# Colors for output
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
BLUE   := $(shell tput -Txterm setaf 4)
RESET  := $(shell tput -Txterm sgr0)

##@ General

help: ## Display this help message
	@echo "$(BLUE)OpenClaw OpenShift Deployment$(RESET)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(YELLOW)<target>$(RESET)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2 } /^##@/ { printf "\n$(GREEN)%s$(RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Deployment

install: ## Install OpenClaw (ENV=lab|production)
	@echo "$(GREEN)Installing OpenClaw (environment: $(ENV))...$(RESET)"
	@./scripts/install.sh $(ENV)

deploy-lab: ## Deploy to lab environment
	@$(MAKE) install ENV=lab

deploy-prod: ## Deploy to production environment
	@$(MAKE) install ENV=production

uninstall: ## Uninstall OpenClaw
	@echo "$(YELLOW)Uninstalling OpenClaw...$(RESET)"
	@./scripts/uninstall.sh

clean: ## Clean deployment (removes all data)
	@echo "$(YELLOW)Cleaning OpenClaw deployment...$(RESET)"
	@./scripts/uninstall.sh

##@ Validation & Testing

validate: ## Validate deployment health
	@echo "$(GREEN)Validating OpenClaw deployment...$(RESET)"
	@./scripts/validate.sh

test-connection: ## Test cluster connection
	@echo "$(GREEN)Testing cluster connection...$(RESET)"
	@oc whoami
	@oc cluster-info | head -n 1
	@echo "Current context: $$(oc config current-context)"

##@ Configuration

secrets: ## Create/update secrets interactively
	@echo "$(GREEN)Configuring secrets...$(RESET)"
	@./scripts/create-secrets.sh

##@ Operations

status: ## Show deployment status
	@echo "$(BLUE)=== Deployment Status ===$(RESET)"
	@oc get deployment,pod,svc,route,pvc -n $(NAMESPACE) -l app.kubernetes.io/name=openclaw 2>/dev/null || echo "No resources found"

pods: ## List pods
	@oc get pods -n $(NAMESPACE) -l app.kubernetes.io/name=openclaw

logs: ## Show logs (follow)
	@echo "$(GREEN)Following logs...$(RESET)"
	@oc logs -f deployment/openclaw -n $(NAMESPACE)

logs-tail: ## Show last 100 lines of logs
	@oc logs deployment/openclaw -n $(NAMESPACE) --tail=100

logs-previous: ## Show logs from previous pod
	@oc logs deployment/openclaw -n $(NAMESPACE) --previous

events: ## Show recent events
	@echo "$(BLUE)=== Recent Events ===$(RESET)"
	@oc get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | tail -n 20

describe: ## Describe deployment
	@oc describe deployment openclaw -n $(NAMESPACE)

shell: ## Open shell in running pod
	@echo "$(GREEN)Opening shell in OpenClaw pod...$(RESET)"
	@oc exec -it deployment/openclaw -n $(NAMESPACE) -- /bin/sh

port-forward: ## Port forward to local machine (18789)
	@echo "$(GREEN)Port forwarding to localhost:18789...$(RESET)"
	@echo "Access OpenClaw at: http://localhost:18789"
	@oc port-forward -n $(NAMESPACE) svc/openclaw 18789:18789

approve-devices: ## Approve pending device pairing requests
	@./scripts/approve-devices.sh

list-devices: ## List all paired and pending devices
	@oc exec -n $(NAMESPACE) deployment/openclaw -c openclaw -- openclaw devices list

##@ Troubleshooting

debug: ## Show debugging information
	@echo "$(BLUE)=== Namespace ===$(RESET)"
	@oc get namespace $(NAMESPACE) 2>/dev/null || echo "Namespace not found"
	@echo ""
	@echo "$(BLUE)=== Service Account ===$(RESET)"
	@oc get serviceaccount openclaw -n $(NAMESPACE) 2>/dev/null || echo "ServiceAccount not found"
	@echo ""
	@echo "$(BLUE)=== RBAC ===$(RESET)"
	@oc get role,rolebinding -n $(NAMESPACE) 2>/dev/null || echo "No RBAC found"
	@echo ""
	@echo "$(BLUE)=== ConfigMap ===$(RESET)"
	@oc get configmap -n $(NAMESPACE) -l app.kubernetes.io/name=openclaw 2>/dev/null || echo "ConfigMap not found"
	@echo ""
	@echo "$(BLUE)=== Secret ===$(RESET)"
	@oc get secret openclaw-secrets -n $(NAMESPACE) 2>/dev/null || echo "Secret not found"
	@echo ""
	@echo "$(BLUE)=== PVC ===$(RESET)"
	@oc get pvc -n $(NAMESPACE) 2>/dev/null || echo "PVC not found"
	@echo ""
	@echo "$(BLUE)=== Pods ===$(RESET)"
	@oc get pods -n $(NAMESPACE) -l app.kubernetes.io/name=openclaw 2>/dev/null || echo "No pods found"
	@echo ""
	@echo "$(BLUE)=== Recent Events ===$(RESET)"
	@oc get events -n $(NAMESPACE) --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -n 10 || echo "No warning events"

pod-describe: ## Describe pod
	@oc describe pod -n $(NAMESPACE) -l app.kubernetes.io/name=openclaw

check-scc: ## Check Security Context Constraints
	@echo "$(BLUE)=== Security Context Constraints ===$(RESET)"
	@oc get scc openclaw-scc 2>/dev/null || echo "SCC not found"
	@echo ""
	@echo "$(BLUE)=== Can use SCC? ===$(RESET)"
	@oc auth can-i use scc/openclaw-scc --as=system:serviceaccount:$(NAMESPACE):openclaw

restart: ## Restart deployment
	@echo "$(GREEN)Restarting OpenClaw deployment...$(RESET)"
	@oc rollout restart deployment openclaw -n $(NAMESPACE)
	@oc rollout status deployment openclaw -n $(NAMESPACE)

##@ Development

build-manifests: ## Build manifests with kustomize
	@echo "$(GREEN)Building manifests for $(ENV) environment...$(RESET)"
	@oc kustomize manifests/$(ENV)

apply-manifests: ## Apply manifests (dry-run)
	@echo "$(GREEN)Applying manifests (dry-run)...$(RESET)"
	@oc apply -k manifests/$(ENV) --dry-run=client

diff: ## Show diff of what would change
	@echo "$(GREEN)Showing diff for $(ENV) environment...$(RESET)"
	@oc diff -k manifests/$(ENV) || true

##@ Cleanup

delete-pvc: ## Delete PersistentVolumeClaim (WARNING: data loss!)
	@echo "$(YELLOW)WARNING: This will delete all workspace data!$(RESET)"
	@read -p "Are you sure? [yes/NO]: " confirm && [ "$$confirm" = "yes" ]
	@oc delete pvc openclaw-data -n $(NAMESPACE)

delete-namespace: ## Delete entire namespace (WARNING: complete removal!)
	@echo "$(YELLOW)WARNING: This will delete the entire namespace and all resources!$(RESET)"
	@read -p "Are you sure? [yes/NO]: " confirm && [ "$$confirm" = "yes" ]
	@oc delete namespace $(NAMESPACE)
