# IaC Multi-Toolbox 🛠️

[](https://www.google.com/search?q=https://ghcr.io/furati/iac-toolbox)
[](https://opensource.org/licenses/MIT)

A high-performance, minimalist containerized environment for **Infrastructure as Code (IaC)**. This toolbox bundles industry-standard provisioning and automation tools into a single, consistent interface, eliminating "it works on my machine" conflicts.

## 🚀 Key Features

* **Multi-Arch Support:** Automatic detection and installation of `govc` for both `x86_64` and `arm64` (Apple Silicon).
* **Dynamic Versioning:** The build system fetches the latest stable versions of Terraform, Packer, and Ansible at build time.
* **UID/GID Mapping:** Seamless host-to-container permission handling. Files created in the container belong to your host user.
* **Docker-out-of-Docker:** The mounted host Docker socket lets you manage host containers from within the toolbox (the bundled Docker CLI talks to the host daemon).
* **OCI Compliant:** Fully labeled according to OpenContainers standards for GitHub Packages integration.

-----

## 📦 Bundled Tools

| Tool | Purpose |
| :--- | :--- |
| **Terraform** | Cloud & Infrastructure Provisioning |
| **Packer** | Automated Machine Image Creation |
| **Ansible** | Configuration Management & App Deployment |
| **govc** | vSphere/ESXi CLI Management |
| **Docker CLI** | Container Lifecycle Management |
| **ansible-lint** | Ansible playbook/role best-practice linting |
| **yamllint** | YAML style & syntax linting |
| **tflint** | Terraform linting (errors, deprecations, provider rules) |

-----

## 🛠 Installation & Usage

### 1\. Prerequisites

Ensure you have **Docker Desktop** (or OrbStack) installed and the Docker socket available.

### 2\. Fast Access (Recommended)

Add this alias to your `~/.zshrc` or `~/.bashrc` to use the toolbox like a native binary:

```bash
alias iac='docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.docker/config.json:/root/.docker/config.json \
  -v "$PWD":/workbench \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  ghcr.io/furati/iac-toolbox'
```

### 3\. Basic Commands

```bash
# Run Terraform
iac terraform plan

# Run Ansible Playbook
iac ansible-playbook site.yml

# Interactive Shell
iac
```

-----

## 🏗 Development & Build System

The project includes a sophisticated `Makefile` to manage the lifecycle of the toolbox.

### Self-Documenting Makefile

Simply run `make` to see all available options:

```text
build           Build the Docker image locally with latest upstream versions
run             Start an interactive shell session in the toolbox
lint            Run ansible-lint, yamllint and tflint against /workbench
scan            Security scan: hadolint (Dockerfile) + trivy (image CVEs)
push            Execute the Ansible build-and-push workflow to GHCR
clean           Remove local images and prune build cache
```

### Linting & Security Scanning

```bash
# Lint mounted IaC code (Ansible + YAML + Terraform)
make lint

# Or call a linter directly inside the toolbox
iac ansible-lint site.yml
iac yamllint .
iac tflint

# Scan the Dockerfile and built image for issues (uses hadolint + trivy)
make scan
```

> `make lint` and `make scan` also run automatically in the CI pipeline before any image is pushed to GHCR.

### Local Deployment

The `make push` target runs an internal Ansible playbook ([build-and-push.yml](build-and-push.yml))
to build and push from your workstation. For day-to-day publishing you normally
rely on CI (below) — this is the manual fallback.

-----

## 🤖 CI/CD & Auto-Updates

All version discovery lives in one place — [scripts/discover-versions.sh](scripts/discover-versions.sh) —
which is shared by the `Makefile` and the GitHub workflows so they can never drift.

| Workflow | Trigger | What it does |
| :--- | :--- | :--- |
| [build.yml](.github/workflows/build.yml) | reusable (`workflow_call`) | hadolint → build amd64 → trivy CVE scan → lint → smoke + functional tests → (optionally) build & push **multi-arch** (amd64 + arm64) |
| [ci.yml](.github/workflows/ci.yml) | push / PR to `main`, manual | Calls `build.yml`. PRs build + test only; pushes to `main` also publish. |
| [auto-update.yml](.github/workflows/auto-update.yml) | **daily** cron, manual | Discovers the latest upstream versions, computes a version tag, and **publishes a fresh image only if that tag isn't already in GHCR**. |

### How auto-update works

The image tag encodes every bundled tool version, e.g.:

```text
tf1.15.6_pk1.15.4_ans2.18.6_govc0.54.1_tflint0.63.1_al24.12.2_alpine3.22
```

The daily job recomputes this tag from the newest upstream releases and checks
GHCR. If the tag already exists, nothing happens; if any tool has a new release,
the tag changes, the build runs through the full test suite, and the new image is
published to `:latest` and the version tag. The **registry is the only state** —
there is no lockfile to maintain.

Every published image is built for **linux/amd64 + linux/arm64**, ships with
SBOM and provenance attestations, and is **signed with cosign** (keyless/OIDC).
Trivy results are uploaded to the repository **Security tab**.

### Verifying an image

```bash
cosign verify ghcr.io/furati/iac-toolbox:latest \
  --certificate-identity-regexp 'https://github.com/furati/IaC-Multi-Toolbox/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

GitHub Actions are pinned to commit SHAs and kept current by Dependabot.

-----

## 🔒 Permission Handling

The container uses a custom `entrypoint.sh` to synchronize permissions:

1. It detects your Mac/Linux **UID** and **GID**.
2. It dynamically maps a container user (`iacuser`) to these IDs.
3. It adjusts `/var/run/docker.sock` permissions to allow non-root Docker commands.

-----

## 📝 License

Distributed under the **MIT License**. See `LICENSE` for more information.

**Maintained by:** Ralf Buhlrich [ralf@buhlrich.com](mailto:ralf@buhlrich.com)
