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

# Default Docker Runtime Configuration
DOCKER_RUN := docker run -it --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v ~/.docker/config.json:/root/.docker/config.json \
    -v $(shell pwd):/workbench \
    -e HOST_UID=$(HOST_UID) \
    -e HOST_GID=$(HOST_GID) \
    $(IMAGE_NAME)

.PHONY: help build run push clean

# Default Target: Displays Help Menu
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
	$(DOCKER_RUN) /bin/sh

push: ## Execute the Ansible workflow (Tagging & GHCR Push)
	@if [ -f $(TOKEN_FILE) ]; then \
		GH_TOKEN=$$(cat $(TOKEN_FILE)); \
	else \
		echo "GitHub Token file ($(TOKEN_FILE)) not found."; \
		read -p "Please enter your GitHub PAT: " secret; \
		GH_TOKEN=$$secret; \
	fi; \
	if [ -z "$$GH_TOKEN" ]; then \
		echo "ERROR: Authentication token is required for push."; exit 1; \
	fi; \
	echo "--- Starting Push Workflow ---"; \
	$(DOCKER_RUN) ansible-playbook build-and-push.yml -e "gh_token=$$GH_TOKEN"

clean: ## Remove local image and prune dangling Docker layers
	docker rmi $(IMAGE_NAME) 2>/dev/null