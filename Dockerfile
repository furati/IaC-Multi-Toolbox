# ==========================================
# Stage 1: Builder (For govc Download)
# ==========================================
FROM alpine:latest AS builder

RUN apk add --no-cache curl tar

# Download the appropriate govc version based on build architecture
# (Supports x86_64 for Intel/AMD and aarch64 for Apple Silicon)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then GOVC_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then GOVC_ARCH="arm64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -L "https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_${GOVC_ARCH}.tar.gz" | tar -xz -C /tmp && \
    mv /tmp/govc /usr/local/bin/govc && \
    chmod +x /usr/local/bin/govc

# ==========================================
# Stage 2: Final Minimal Image
# ==========================================
FROM alpine:latest

# Define Build Arguments (passed from Makefile/Ansible)
ARG TERRAFORM_VERSION
ARG PACKER_VERSION
ARG ANSIBLE_VERSION
ARG PYTHON_VERSION
ARG GOVC_VERSION
ARG REPO_URL="https://github.com/furati/IaC-Multi-Toolbox.git"

# OCI Standard Labels for GitHub Integration
LABEL org.opencontainers.image.title="IaC Multi-Toolbox" \
    org.opencontainers.image.description="Minimalist container with Terraform, Packer, Ansible, and govc" \
    org.opencontainers.image.url=${REPO_URL} \
    org.opencontainers.image.source=${REPO_URL} \
    org.opencontainers.image.version=${TERRAFORM_VERSION} \
    org.opencontainers.image.licenses="MIT" \
    # Custom tool version metadata
    tool.terraform.version=${TERRAFORM_VERSION} \
    tool.packer.version=${PACKER_VERSION} \
    tool.ansible.version=${ANSIBLE_VERSION} \
    tool.python.version=${PYTHON_VERSION} \
    tool.govc.version=${GOVC_VERSION} \
    # Author/Vendor information
    org.opencontainers.image.vendor="Ralf Buhlrich <ralf@buhlrich.com>"

# 1. Install System Tools and Python Libraries for Ansible
RUN apk add --no-cache \
    ansible \
    openssh-client \
    git \
    ca-certificates \
    su-exec \
    python3 \
    py3-pip \
    docker-cli

# 2. Install Python dependencies for the Ansible Docker Module
# Note: --break-system-packages is used as Alpine strictly manages pip.
# This is safe and standard practice within isolated containers.
RUN pip install --no-cache-dir --break-system-packages requests docker

# 3. Copy binaries from official sources and builder stage
COPY --from=hashicorp/terraform:latest /bin/terraform /usr/local/bin/terraform
COPY --from=hashicorp/packer:latest /bin/packer /usr/local/bin/packer
COPY --from=builder /usr/local/bin/govc /usr/local/bin/govc

# Set the primary working directory
WORKDIR /workbench

# 4. Configure Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command if no arguments are provided
CMD ["/bin/sh"]