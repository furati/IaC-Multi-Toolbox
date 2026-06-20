# ==========================================
# Core Identifiers (defined first so version discovery can reference them)
# ==========================================
IMAGE_NAME := iac-toolbox
TOKEN_FILE := .github_token
DISCOVER   := ./scripts/discover-versions.sh

# ==========================================
# Dynamic Tool Version Discovery (single source of truth: scripts/)
# Terraform/Packer/govc/tflint track latest upstream; apk tools track the
# pinned Alpine release. Discovered versions are passed as build args and
# pinned inside the image, so a given build is fully reproducible.
# ==========================================
ALPINE_VER := $(shell $(DISCOVER) alpine)
TF_VER     := $(shell $(DISCOVER) terraform)
PK_VER     := $(shell $(DISCOVER) packer)
ANS_VER    := $(shell $(DISCOVER) ansible)
PY_VER     := $(shell $(DISCOVER) python)
GV_VER     := $(shell $(DISCOVER) govc)
AL_VER     := $(shell $(DISCOVER) ansible-lint)
TFL_VER    := $(shell $(DISCOVER) tflint)

# Exporting Host IDs for Permission Mapping
export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)

# 1. Robust TTY Detection
# We check if we are in a terminal AND not in a CI environment (GitHub Actions)
INTERACTIVE := $(shell [ -t 0 ] && [ -z "$$GITHUB_ACTIONS" ] && echo "-it" || echo "")

# 2. Base Docker Command (Without -it)
# We use this as a template for all commands
DOCKER_BASE := docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    $(shell [ -f $(HOME)/.docker/config.json ] && echo "-v $(HOME)/.docker/config.json:/root/.docker/config.json") \
    -v $(shell pwd):/workbench \
    -e HOST_UID=$(HOST_UID) \
    -e HOST_GID=$(HOST_GID) \
    $(IMAGE_NAME)

.PHONY: help build run push clean lint scan test test-functional

help: ## Display this help information
	@echo "-----------------------------------------------------------------------"
	@echo "IaC Multi-Toolbox - Available Commands:"
	@echo "-----------------------------------------------------------------------"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo "-----------------------------------------------------------------------"
	@echo "Current Versions (Dynamically Discovered):"
	@echo "Terraform: $(TF_VER) | Packer: $(PK_VER) | Ansible: $(ANS_VER)"
	@echo "Linters -> ansible-lint: $(AL_VER) | tflint: $(TFL_VER)"

build: ## Build the Docker image locally with upstream tool versions
	@echo "--- Starting Build Process ---"
	docker build -t $(IMAGE_NAME) \
		--build-arg TERRAFORM_VERSION=$(TF_VER) \
		--build-arg PACKER_VERSION=$(PK_VER) \
		--build-arg ANSIBLE_VERSION=$(ANS_VER) \
		--build-arg PYTHON_VERSION=$(PY_VER) \
		--build-arg GOVC_VERSION=$(GV_VER) \
		--build-arg TFLINT_VERSION=$(TFL_VER) \
		--build-arg ANSIBLE_LINT_VERSION=$(AL_VER) \
		--build-arg ALPINE_VERSION=$(ALPINE_VER) .

run: ## Launch an interactive shell session within the toolbox
	$(DOCKER_BASE) $(INTERACTIVE) /bin/sh

push: ## Execute the Ansible workflow (Tagging & GHCR Push)
	@if [ -n "$(GITHUB_TOKEN)" ]; then \
		TOKEN="$(GITHUB_TOKEN)"; \
	elif [ -f $(TOKEN_FILE) ]; then \
		TOKEN=$$(cat $(TOKEN_FILE)); \
	else \
		echo "No token found. Please enter your GitHub PAT: "; \
		read secret; \
		TOKEN=$$secret; \
	fi; \
	if [ -z "$$TOKEN" ]; then \
		echo "ERROR: Authentication token is required."; exit 1; \
	fi; \
	echo "--- Starting Push Workflow ---"; \
	$(DOCKER_BASE) ansible-playbook build-and-push.yml -e "gh_token=$$TOKEN"

clean: ## Remove local image and prune dangling Docker layers
	docker rmi $(IMAGE_NAME) 2>/dev/null || true

test: ## Verify tool installations and versions within the container
	@echo "--- Starting Container Smoke Tests ---"
	@echo "Testing Terraform: $(TF_VER)..."
	@$(DOCKER_BASE) terraform version | grep -q "v$(TF_VER)" && echo "  OK"
	@echo "Testing Packer: $(PK_VER)..."
	@$(DOCKER_BASE) packer version | grep -q "$(PK_VER)" && echo "  OK"
	@echo "Testing Ansible: $(ANS_VER)..."
	@$(DOCKER_BASE) ansible --version | grep -q "$(ANS_VER)" && echo "  OK"
	@echo "Testing govc: $(GV_VER)..."
	@$(DOCKER_BASE) govc version | grep -q "$(GV_VER)" && echo "  OK"
	@echo "✅ All smoke tests passed!"

test-functional: ## Test actual tool functionality (Init, Syntax, etc.)
	@echo "--- Starting Functional Tests ---"
	@echo "Testing Terraform provider initialization..."
	@$(DOCKER_BASE) sh -c 'echo "provider \"local\" {}" > test.tf && terraform init && rm -rf .terraform* test.tf'
	@echo "Testing Ansible playbook syntax check..."
	@$(DOCKER_BASE) ansible-playbook build-and-push.yml --syntax-check
	@echo "Testing Packer syntax..."
	@$(DOCKER_BASE) packer --version
	@echo "✅ All functional tests passed!"

lint: ## Run ansible-lint, yamllint and tflint against /workbench
	@echo "--- Running Linters ---"
	@echo "yamllint (YAML style)..."
	@$(DOCKER_BASE) yamllint .
	@echo "ansible-lint (playbook best practices)..."
	@$(DOCKER_BASE) ansible-lint
	@echo "tflint (Terraform)... (skipped when no .tf files present)"
	@$(DOCKER_BASE) sh -c 'if ls *.tf >/dev/null 2>&1; then tflint --init && tflint; else echo "  no .tf files, skipping"; fi'
	@echo "✅ Linting complete!"

scan: ## Security scan: hadolint (Dockerfile) + trivy (image CVEs)
	@echo "--- Dockerfile Lint (hadolint) ---"
	docker run --rm -v $(shell pwd):/repo -w /repo hadolint/hadolint hadolint Dockerfile
	@echo "--- Image CVE Scan (trivy) ---"
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL --exit-code 1 $(IMAGE_NAME)
	@echo "✅ Security scan passed!"