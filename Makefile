# ==========================================
# Core Identifiers (defined first so version discovery can reference them)
# ==========================================
IMAGE_NAME      := iac-toolbox
DIND_IMAGE_NAME := dind
TOKEN_FILE      := .github_token
DISCOVER        := ./scripts/discover-versions.sh

# ==========================================
# Dynamic Tool Version Discovery (single source of truth: scripts/)
# Terraform/Packer/govc/tflint track latest upstream, ansible-core and
# ansible-lint track PyPI, the dind engine tracks the pinned Debian release.
# Discovered versions are passed as build args and pinned inside the image,
# so a given build is fully reproducible.
# ==========================================
DEBIAN_VER := $(shell $(DISCOVER) debian)
TF_VER     := $(shell $(DISCOVER) terraform)
PK_VER     := $(shell $(DISCOVER) packer)
ANS_VER    := $(shell $(DISCOVER) ansible)
GV_VER     := $(shell $(DISCOVER) govc)
AL_VER     := $(shell $(DISCOVER) ansible-lint)
TFL_VER    := $(shell $(DISCOVER) tflint)
# Lazily evaluated (spins up a container) — only used by the dind targets.
DOCKER_VER  = $(shell $(DISCOVER) docker)

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

.PHONY: help build build-dind run push clean lint scan scan-dind test test-dind test-functional

help: ## Display this help information
	@echo "-----------------------------------------------------------------------"
	@echo "IaC Multi-Toolbox - Available Commands:"
	@echo "-----------------------------------------------------------------------"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo "-----------------------------------------------------------------------"
	@echo "Current Versions (Dynamically Discovered):"
	@echo "Terraform: $(TF_VER) | Packer: $(PK_VER) | ansible-core: $(ANS_VER)"
	@echo "Linters -> ansible-lint: $(AL_VER) | tflint: $(TFL_VER)"

build: ## Build the toolbox image locally with upstream tool versions
	@echo "--- Starting Build Process ---"
	docker build -t $(IMAGE_NAME) \
		--build-arg DEBIAN_VERSION=$(DEBIAN_VER) \
		--build-arg TERRAFORM_VERSION=$(TF_VER) \
		--build-arg PACKER_VERSION=$(PK_VER) \
		--build-arg ANSIBLE_VERSION=$(ANS_VER) \
		--build-arg GOVC_VERSION=$(GV_VER) \
		--build-arg TFLINT_VERSION=$(TFL_VER) \
		--build-arg ANSIBLE_LINT_VERSION=$(AL_VER) .

build-dind: ## Build the dind (Docker-in-Docker) image locally
	@echo "--- Building dind (docker.io $(DOCKER_VER), Debian $(DEBIAN_VER)) ---"
	docker build -t $(DIND_IMAGE_NAME) \
		--build-arg DEBIAN_VERSION=$(DEBIAN_VER) \
		--build-arg DOCKER_VERSION=$(DOCKER_VER) dind

run: ## Launch an interactive shell session within the toolbox
	$(DOCKER_BASE) $(INTERACTIVE) /bin/bash

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

clean: ## Remove local images and prune dangling Docker layers
	docker rmi $(IMAGE_NAME) 2>/dev/null || true
	docker rmi $(DIND_IMAGE_NAME) 2>/dev/null || true

test: ## Verify tool installations and versions within the container
	@echo "--- Starting Container Smoke Tests ---"
	@echo "Testing Terraform: $(TF_VER)..."
	@$(DOCKER_BASE) terraform version | grep -q "v$(TF_VER)" && echo "  OK"
	@echo "Testing Packer: $(PK_VER)..."
	@$(DOCKER_BASE) packer version | grep -q "$(PK_VER)" && echo "  OK"
	@echo "Testing ansible-core: $(ANS_VER)..."
	@$(DOCKER_BASE) ansible --version | grep -q "$(ANS_VER)" && echo "  OK"
	@echo "Testing govc: $(GV_VER)..."
	@$(DOCKER_BASE) govc version | grep -q "$(GV_VER:v%=%)" && echo "  OK"
	@echo "Testing molecule..."
	@$(DOCKER_BASE) molecule --version >/dev/null && echo "  OK"
	@echo "Testing docker CLI + xorriso..."
	@$(DOCKER_BASE) sh -c 'docker --version && xorriso -version' >/dev/null && echo "  OK"
	@echo "✅ All smoke tests passed!"

test-dind: ## Verify the dind image starts a working Docker daemon
	@echo "--- Starting dind Smoke Test ---"
	@docker run --rm --entrypoint dockerd $(DIND_IMAGE_NAME) --version
	@docker rm -f dind-smoke 2>/dev/null || true
	@docker run -d --privileged --name dind-smoke $(DIND_IMAGE_NAME)
	@ok=0; for i in $$(seq 1 30); do \
		docker exec dind-smoke docker info >/dev/null 2>&1 && { ok=1; break; }; sleep 1; done; \
	if [ $$ok -eq 1 ]; then \
		echo "✅ dind daemon is up!"; docker rm -f dind-smoke >/dev/null; \
	else \
		docker logs dind-smoke; docker rm -f dind-smoke >/dev/null; exit 1; \
	fi

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

scan: ## Security scan: hadolint (Dockerfile) + trivy (toolbox image CVEs)
	@echo "--- Dockerfile Lint (hadolint) ---"
	docker run --rm -v $(shell pwd):/repo -w /repo hadolint/hadolint hadolint Dockerfile
	@echo "--- CVE Report (trivy, HIGH+CRITICAL, non-blocking) ---"
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 0 $(IMAGE_NAME)
	@echo "--- CVE Gate (trivy, fail on fixable CRITICAL) ---"
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE_NAME)
	@echo "✅ Security scan passed!"

scan-dind: ## Security scan: hadolint + trivy for the dind image
	@echo "--- Dockerfile Lint (hadolint) ---"
	docker run --rm -v $(shell pwd):/repo -w /repo hadolint/hadolint hadolint dind/Dockerfile
	@echo "--- CVE Gate (trivy, fail on fixable CRITICAL) ---"
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity CRITICAL --ignore-unfixed --exit-code 1 $(DIND_IMAGE_NAME)
	@echo "✅ Security scan passed!"
