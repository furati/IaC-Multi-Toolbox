# check=skip=InvalidDefaultArgInFrom
# The version ARGs in the FROM lines are intentionally required (no default):
# a bare `docker build` should fail loudly rather than silently use :latest.

# ==========================================
# Global build args (available to FROM lines below).
# All versions are *required* and supplied by the Makefile / CI workflows,
# which discover the latest upstream releases. Pinning them here makes a given
# build fully reproducible: same args in -> same image out.
# ==========================================
ARG DEBIAN_VERSION=13
ARG TERRAFORM_VERSION
ARG PACKER_VERSION

# ==========================================
# Pinned upstream tool images (versioned tags, not :latest).
# terraform/packer are static Go binaries, so copying them out of the
# Alpine-based upstream images onto Debian works fine.
# ==========================================
FROM hashicorp/terraform:${TERRAFORM_VERSION} AS terraform
FROM hashicorp/packer:${PACKER_VERSION} AS packer

# ==========================================
# Stage 1: Builder (downloads govc + tflint, builds the Python venv and
# installs the Ansible collections — nothing from this stage's apt layer
# leaks into the final image)
# ==========================================
FROM debian:${DEBIAN_VERSION}-slim AS builder

# Fail pipelines if any stage errors (e.g. a failed curl piped into tar).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
    unzip \
    git \
    python3 \
    python3-venv && \
    rm -rf /var/lib/apt/lists/*

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

# Isolated Python environment, copied wholesale into the final image.
# ansible-core and ansible-lint are pinned to the discovered versions; the
# supporting libraries float and are refreshed with every rebuild.
#   - molecule (+docker plugin) -> test roles/collections against containers
#   - docker (Python SDK)       -> community.docker / docker-out-of-docker
#   - pyvmomi                   -> community.vmware (vSphere)
#   - requests                  -> nutanix.ncp and friends
ARG ANSIBLE_VERSION
ARG ANSIBLE_LINT_VERSION
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
RUN pip install --no-cache-dir \
    "ansible-core==${ANSIBLE_VERSION}" \
    "ansible-lint==${ANSIBLE_LINT_VERSION}" \
    yamllint \
    molecule \
    "molecule-plugins[docker]" \
    docker \
    pyvmomi \
    requests

# Ansible collections into a global, world-readable path (baked in, so no
# runtime galaxy install is needed for the common providers).
RUN mkdir -p /usr/share/ansible/collections && \
    ansible-galaxy collection install \
    community.general \
    community.docker \
    community.vmware \
    community.postgresql \
    ansible.posix \
    nutanix.ncp \
    -p /usr/share/ansible/collections && \
    chmod -R a+rX /usr/share/ansible/collections

# ==========================================
# Stage 2: Final image (Debian 13 slim)
# ==========================================
FROM debian:${DEBIAN_VERSION}-slim

# Re-declare build args needed in this stage (ARGs do not cross stages).
ARG DEBIAN_VERSION
ARG TERRAFORM_VERSION
ARG PACKER_VERSION
ARG ANSIBLE_VERSION
ARG GOVC_VERSION
ARG TFLINT_VERSION
ARG ANSIBLE_LINT_VERSION
ARG REPO_URL="https://github.com/furati/IaC-Multi-Toolbox.git"

# Fail pipelines if any stage in a piped RUN errors.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# OCI Standard Labels for GitHub Integration
LABEL org.opencontainers.image.title="IaC Multi-Toolbox" \
    org.opencontainers.image.description="IaC toolbox and devcontainer base with Terraform, Packer, Ansible, molecule and govc (Debian 13)" \
    org.opencontainers.image.url=${REPO_URL} \
    org.opencontainers.image.source=${REPO_URL} \
    org.opencontainers.image.version=${TERRAFORM_VERSION} \
    org.opencontainers.image.licenses="MIT" \
    # Custom tool version metadata
    tool.terraform.version=${TERRAFORM_VERSION} \
    tool.packer.version=${PACKER_VERSION} \
    tool.ansible-core.version=${ANSIBLE_VERSION} \
    tool.govc.version=${GOVC_VERSION} \
    tool.tflint.version=${TFLINT_VERSION} \
    tool.ansible-lint.version=${ANSIBLE_LINT_VERSION} \
    os.debian.version=${DEBIAN_VERSION} \
    # Author/Vendor information
    org.opencontainers.image.vendor="Ralf Buhlrich <ralf@buhlrich.com>"

# 1. Runtime packages. `apt-get upgrade` first pulls security fixes for
# base-image packages (e.g. openssl) that `install` alone would not refresh.
#   - docker-cli    -> docker-out-of-docker against a mounted socket or dind
#   - xorriso, cpio -> ISO (re)mastering for Packer image builds
#   - sudo          -> passwordless for the 'dev' user (devcontainer comfort)
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    python3 \
    ca-certificates \
    git \
    openssh-client \
    sshpass \
    curl \
    jq \
    unzip \
    make \
    cpio \
    xorriso \
    less \
    bash-completion \
    gosu \
    sudo \
    locales \
    docker-cli && \
    rm -rf /var/lib/apt/lists/*

# 1b. Generate the locales terminals commonly forward (VS Code/macOS sends
# en_US.UTF-8 into devcontainer sessions; slim images ship none).
RUN sed -i -e 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
        -e 's/^# *de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8

# 2. Non-root default user (devcontainer convention: UID/GID 1000) with
# passwordless sudo for ad-hoc package installs during daily work.
RUN groupadd --gid 1000 dev && \
    useradd --uid 1000 --gid dev --create-home --shell /bin/bash dev && \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev

# 3. Pull the prepared venv, collections and binaries from the build stages.
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /usr/share/ansible/collections /usr/share/ansible/collections
COPY --from=terraform /bin/terraform /usr/local/bin/terraform
COPY --from=packer /bin/packer /usr/local/bin/packer
COPY --from=builder /usr/local/bin/govc /usr/local/bin/govc
COPY --from=builder /usr/local/bin/tflint /usr/local/bin/tflint

# 4. Environment: venv first in PATH, collections discoverable for Ansible.
ENV PATH="/opt/venv/bin:${PATH}" \
    ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# 5. Primary working directory (mounted project), owned by the default user.
WORKDIR /workbench
RUN chown dev:dev /workbench

# 6. Entrypoint. The image stays root at entry (no USER switch) so the
# entrypoint can create the HOST_UID/HOST_GID-mapped user and drop privileges
# via gosu; without HOST_UID/GID it falls back to the non-root 'dev' user.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
