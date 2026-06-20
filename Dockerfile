# check=skip=InvalidDefaultArgInFrom
# The version ARGs in the FROM lines are intentionally required (no default):
# a bare `docker build` should fail loudly rather than silently use :latest.

# ==========================================
# Global build args (available to FROM lines below).
# All versions are *required* and supplied by the Makefile / Ansible playbook,
# which discover the latest upstream releases. Pinning them here makes a given
# build fully reproducible: same args in -> same image out.
# ==========================================
ARG ALPINE_VERSION=3.22
ARG TERRAFORM_VERSION
ARG PACKER_VERSION

# ==========================================
# Pinned upstream tool images (versioned tags, not :latest)
# ==========================================
FROM hashicorp/terraform:${TERRAFORM_VERSION} AS terraform
FROM hashicorp/packer:${PACKER_VERSION} AS packer

# ==========================================
# Stage 1: Builder (downloads govc + tflint at pinned versions)
# ==========================================
FROM alpine:${ALPINE_VERSION} AS builder

# Fail pipelines if any stage errors (e.g. a failed curl piped into tar).
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

RUN apk add --no-cache curl tar unzip

# Download the pinned govc version for the build architecture.
# (Supports x86_64 for Intel/AMD and aarch64 for Apple Silicon)
# GOVC_VERSION includes the leading "v" (e.g. v0.54.1), matching the release tag.
ARG GOVC_VERSION
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then GOVC_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then GOVC_ARCH="arm64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -fL "https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govc_Linux_${GOVC_ARCH}.tar.gz" | tar -xz -C /tmp && \
    mv /tmp/govc /usr/local/bin/govc && \
    chmod +x /usr/local/bin/govc

# Download the pinned tflint version (TFLINT_VERSION has no leading "v").
ARG TFLINT_VERSION
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then TFLINT_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then TFLINT_ARCH="arm64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -fL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${TFLINT_ARCH}.zip" -o /tmp/tflint.zip && \
    unzip /tmp/tflint.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/tflint && \
    rm /tmp/tflint.zip

# ==========================================
# Stage 2: Final Minimal Image
# ==========================================
FROM alpine:${ALPINE_VERSION}

# Re-declare build args needed in this stage (ARGs do not cross stages).
ARG ALPINE_VERSION
ARG TERRAFORM_VERSION
ARG PACKER_VERSION
ARG ANSIBLE_VERSION
ARG PYTHON_VERSION
ARG GOVC_VERSION
ARG TFLINT_VERSION
ARG ANSIBLE_LINT_VERSION
ARG REPO_URL="https://github.com/furati/IaC-Multi-Toolbox.git"

# Fail pipelines if any stage in a piped RUN errors.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

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
    tool.tflint.version=${TFLINT_VERSION} \
    tool.ansible-lint.version=${ANSIBLE_LINT_VERSION} \
    tool.alpine.version=${ALPINE_VERSION} \
    # Author/Vendor information
    org.opencontainers.image.vendor="Ralf Buhlrich <ralf@buhlrich.com>"

# 1. Install System Tools and Python Libraries for Ansible
# `apk upgrade` first pulls security fixes for base-image packages (e.g. openssl)
# that `apk add` alone would not refresh.
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    ansible-core \
    ansible-lint \
    yamllint \
    openssh-client \
    git \
    ca-certificates \
    su-exec \
    python3 \
    py3-pip \
    docker-cli && \
    # Install Python deps and immediately clean up
    pip install --no-cache-dir --break-system-packages requests docker && \
    # Uninstall pip to save space, but keep python3 for Ansible
    apk del py3-pip && \
    # Aggressive Cleanup of Python bytecode and temp files
    find /usr/lib/python* -name __pycache__ -exec rm -rf {} + && \
    rm -rf /root/.cache /tmp/*

# 1b. Assert the apk-provided ansible-core matches the discovered/label version.
# Pinning ALPINE_VERSION makes this deterministic; this guards against label drift.
RUN INSTALLED=$(ansible --version | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+') && \
    if [ -n "${ANSIBLE_VERSION}" ] && [ "$INSTALLED" != "${ANSIBLE_VERSION}" ]; then \
        echo "ERROR: ansible-core ${INSTALLED} installed but label claims ${ANSIBLE_VERSION}." >&2; \
        echo "Re-run discovery (make build) so the version arg matches alpine:${ALPINE_VERSION}." >&2; \
        exit 1; \
    fi

# 2. Install Ansible collection to a global, readable path
RUN mkdir -p /usr/share/ansible/collections && \
    ansible-galaxy collection install community.docker -p /usr/share/ansible/collections && \
    chmod -R 755 /usr/share/ansible/collections

# 3. Ensure Ansible knows where to look
ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections

# 4. Copy binaries from the pinned tool stages and the builder stage
COPY --from=terraform /bin/terraform /usr/local/bin/terraform
COPY --from=packer /bin/packer /usr/local/bin/packer
COPY --from=builder /usr/local/bin/govc /usr/local/bin/govc
COPY --from=builder /usr/local/bin/tflint /usr/local/bin/tflint

# 5. Set the primary working directory
WORKDIR /workbench

# 6. Configure Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 7. Default command if no arguments are provided
CMD ["/bin/sh"]