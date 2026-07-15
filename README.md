# IaC Multi-Toolbox 🛠️

A containerized environment for **Infrastructure as Code (IaC)** on **Debian 13
(Trixie)** — usable three ways:

1. as a **CLI toolbox** (`docker run` / shell alias),
2. as a **VS Code devcontainer** base for daily work,
3. together with the bundled **dind** image as a Docker daemon for CI services.

It bundles industry-standard provisioning and automation tools into a single,
consistent interface, eliminating "it works on my machine" conflicts.

## 🚀 Key Features

* **Debian 13 base:** glibc, apt and a full `bash` — the same foundation as the
  target systems, and devcontainer-friendly (Alpine quirks eliminated).
* **Devcontainer-ready:** non-root `dev` user (UID/GID 1000) with passwordless
  sudo, git/ssh on board, reference `.devcontainer/devcontainer.json` included.
* **Multi-Arch Support:** `linux/amd64` and `linux/arm64` (Apple Silicon).
* **Dynamic Versioning:** The build system fetches the latest stable versions of
  Terraform, Packer and ansible-core at build time; the registry tag encodes them.
* **UID/GID Mapping:** Seamless host-to-container permission handling. Files
  created in the container belong to your host user.
* **Docker-out-of-Docker:** The mounted host Docker socket lets you manage host
  containers from within the toolbox (the bundled Docker CLI talks to the host
  daemon). Alternatively point `DOCKER_HOST` at the **dind** image.
* **OCI Compliant:** Fully labeled, signed (cosign), with SBOM + provenance.

-----

## 📦 Images

| Image | Purpose |
| :--- | :--- |
| `ghcr.io/furati/iac-toolbox` | The toolbox / devcontainer base described below |
| `ghcr.io/furati/dind` | Docker-in-Docker daemon (dockerd from the Debian archive) for CI `services:` or an isolated local daemon |

### Bundled tools (iac-toolbox)

| Tool | Purpose |
| :--- | :--- |
| **Terraform** | Cloud & Infrastructure Provisioning |
| **Packer** | Automated Machine Image Creation |
| **ansible-core** | Configuration Management & App Deployment (venv, latest PyPI) |
| **molecule** (+docker driver) | Role/collection testing |
| **govc** | vSphere/ESXi CLI Management |
| **Docker CLI** | Container lifecycle management (docker-out-of-docker) |
| **xorriso + cpio** | ISO (re)mastering for Packer image builds |
| **ansible-lint / yamllint / tflint** | Linting for Ansible, YAML and Terraform |

Baked-in Ansible collections (no runtime galaxy install needed):
`community.general`, `community.docker`, `community.vmware`,
`community.postgresql`, `ansible.posix`, `nutanix.ncp` — plus `pyvmomi` and the
Docker SDK in the Python venv. A project-local `requirements.yml` is installed
automatically at container start.

-----

## 🖥 Usage as a VS Code Devcontainer

Copy [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) into
your project (or reference the image directly):

```jsonc
{
  "name": "IaC Toolbox",
  "image": "ghcr.io/furati/iac-toolbox:latest",
  "remoteUser": "dev",
  "updateRemoteUserUID": true,
  "mounts": [
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
  ]
}
```

VS Code → "Reopen in Container" and you get the full toolchain, running as the
non-root `dev` user with passwordless sudo for ad-hoc `apt` installs. The
mounted socket makes `docker` and molecule's docker driver work immediately.

-----

## 🛠 Usage as a CLI Toolbox

### Fast Access (Recommended)

Add this alias to your `~/.zshrc` or `~/.bashrc` to use the toolbox like a
native binary:

```bash
alias iac='docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.docker/config.json:/root/.docker/config.json \
  -v "$PWD":/workbench \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  ghcr.io/furati/iac-toolbox'
```

### Basic Commands

```bash
# Run Terraform
iac terraform plan

# Run Ansible Playbook
iac ansible-playbook site.yml

# Test a role with molecule
iac molecule test

# Interactive Shell
iac
```

Without `HOST_UID`/`HOST_GID` the entrypoint drops to the built-in non-root
`dev` user; `RUN_AS_ROOT=1` skips the privilege drop entirely.

-----

## 🐳 Usage of the dind image

As a CI service (GitLab CI example):

```yaml
services:
  - name: ghcr.io/furati/dind:latest
    alias: docker
variables:
  DOCKER_HOST: tcp://docker:2375
  DOCKER_TLS_CERTDIR: ""
```

Or locally via compose profile (isolated daemon instead of the host socket):

```bash
docker compose --profile dind up -d dind
DOCKER_HOST=tcp://localhost:2375 docker info
```

Set `DOCKER_TLS_CERTDIR=/certs` to enable the TLS mode on port 2376 (a
self-signed CA/server/client set is generated on first start). CI runners whose
per-build network breaks nested DNS can pass resolvers via `DOCKERD_DNS`.

-----

## 🏗 Development & Build System

The project includes a self-documenting `Makefile` — run `make` to see all
options:

```text
build           Build the toolbox image locally with upstream tool versions
build-dind      Build the dind (Docker-in-Docker) image locally
run             Start an interactive shell session in the toolbox
lint            Run ansible-lint, yamllint and tflint against /workbench
scan            Security scan: hadolint (Dockerfile) + trivy (toolbox CVEs)
scan-dind       Security scan for the dind image
test            Smoke-test tool installations and versions
test-dind       Verify the dind image starts a working Docker daemon
test-functional Test actual tool functionality (init, syntax checks)
push            Execute the Ansible build-and-push workflow to GHCR
clean           Remove local images
```

### Linting & Security Scanning

```bash
make lint   # Lint mounted IaC code (Ansible + YAML + Terraform)
make scan   # hadolint + trivy CVE scan

# Or call a linter directly inside the toolbox
iac ansible-lint site.yml
iac yamllint .
iac tflint
```

> `make lint` and `make scan` also run automatically in the CI pipeline before
> any image is pushed to GHCR.

-----

## 🤖 CI/CD & Auto-Updates

All version discovery lives in one place —
[scripts/discover-versions.sh](scripts/discover-versions.sh) — which is shared
by the `Makefile` and the GitHub workflows so they can never drift.

| Workflow | Trigger | What it does |
| :--- | :--- | :--- |
| [build.yml](.github/workflows/build.yml) | reusable (`workflow_call`) | Per image: hadolint → build amd64 → trivy CVE scan → lint → smoke + functional tests → (optionally) build & push **multi-arch** (amd64 + arm64) |
| [ci.yml](.github/workflows/ci.yml) | push / PR to `main`, manual | Calls `build.yml`. PRs build + test only; pushes to `main` also publish. |
| [auto-update.yml](.github/workflows/auto-update.yml) | **daily** cron, manual | Discovers the latest upstream versions, computes both version tags, and **publishes fresh images only if a tag isn't already in GHCR**. |

### How auto-update works

The image tags encode every bundled tool version, e.g.:

```text
iac-toolbox:  tf1.15.6_pk1.15.4_ans2.19.5_govc0.54.1_tflint0.63.1_al25.9.2_deb13
dind:         docker26.1.5_deb13
```

The daily job recomputes these tags from the newest upstream releases (PyPI for
ansible-core/ansible-lint, the Debian archive for the dind engine) and checks
GHCR. If a tag already exists, nothing happens; if any tool has a new release,
the tag changes, the build runs through the full test suite, and the new image
is published to `:latest` and the version tag. The **registry is the only
state** — there is no lockfile to maintain.

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

The toolbox uses a custom [entrypoint.sh](entrypoint.sh):

1. With `HOST_UID`/`HOST_GID` set, a container user is mapped to those IDs
   (gosu) so files on mounted volumes belong to you.
2. Without them, it drops to the built-in non-root `dev` user.
3. A mounted `/var/run/docker.sock` is made usable via its owning group —
   no `chmod 666`.
4. A `requirements.yml` in the project root is installed via ansible-galaxy
   at start, as the target user.

-----

## 📝 License

Distributed under the **MIT License**. See `LICENSE` for more information.

**Maintained by:** Ralf Buhlrich [ralf@buhlrich.com](mailto:ralf@buhlrich.com)
