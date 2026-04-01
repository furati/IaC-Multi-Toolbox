# ==========================================
# Dynamic Tool Version Discovery
# ==========================================
TF_VER  := $(shell docker run --rm hashicorp/terraform:latest version -json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
PK_VER  := $(shell docker run --rm hashicorp/packer:latest version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
ANS_VER := $(shell docker run --rm alpine:latest sh -c "apk add --no-cache ansible > /dev/null && ansible --version" | head -n 1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
PY_VER  := $(shell docker run --rm alpine:latest sh -c "apk add --no-cache python3 > /dev/null && python3 --version" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
GV_VER  := v0.35.0

# Exporting Host IDs for Permission Mapping
export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)
IMAGE_NAME := iac-toolbox
TOKEN_FILE := .github_token

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

.PHONY: help build run push clean

help: ## Display this help information
	@echo "-----------------------------------------------------------------------"
	@echo "IaC Multi-Toolbox - Available Commands:"
	@echo "-----------------------------------------------------------------------"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo "-----------------------------------------------------------------------"
	@echo "Current Versions (Dynamically Discovered):"
	@echo "Terraform: $(TF_VER) | Packer: $(PK_VER) | Ansible: $(ANS_VER)"

build: ## Build the Docker image locally with upstream tool versions
	@echo "--- Starting Build Process ---"
	docker build -t $(IMAGE_NAME) \
		--build-arg TERRAFORM_VERSION=$(TF_VER) \
		--build-arg PACKER_VERSION=$(PK_VER) \
		--build-arg ANSIBLE_VERSION=$(ANS_VER) \
		--build-arg PYTHON_VERSION=$(PY_VER) \
		--build-arg GOVC_VERSION=$(GV_VER) .

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
	@echo "Testing Terraform..."
	@$(DOCKER_BASE) terraform version | grep -q "v$(TF_VER)"
	@echo "Testing Packer..."
	@$(DOCKER_BASE) packer version | grep -q "$(PK_VER)"
	@echo "Testing Ansible..."
	@$(DOCKER_BASE) ansible --version | grep -q "$(ANS_VER)"
	@echo "Testing govc..."
	@$(DOCKER_BASE) govc version | grep -q "$(GV_VER)"
	@echo "Testing Python..."
	@$(DOCKER_BASE) python3 --version | grep -q "$(PY_VER)"
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