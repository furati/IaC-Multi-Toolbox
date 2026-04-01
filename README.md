# IaC Multi-Toolbox 🛠️

[](https://www.google.com/search?q=https://ghcr.io/furati/iac-toolbox)
[](https://opensource.org/licenses/MIT)

A high-performance, minimalist containerized environment for **Infrastructure as Code (IaC)**. This toolbox bundles industry-standard provisioning and automation tools into a single, consistent interface, eliminating "it works on my machine" conflicts.

## 🚀 Key Features

* **Multi-Arch Support:** Automatic detection and installation of `govc` for both `x86_64` and `arm64` (Apple Silicon).
* **Dynamic Versioning:** The build system fetches the latest stable versions of Terraform, Packer, and Ansible at build time.
* **UID/GID Mapping:** Seamless host-to-container permission handling. Files created in the container belong to your host user.
* **DIND Capability:** Docker-CLI integration allows managing host Docker containers from within the toolbox.
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
push            Execute the Ansible build-and-push workflow to GHCR
clean           Remove local images and prune build cache
```

### Automated Deployment

The `push` target utilizes an internal Ansible playbook to:

1. Validate tool versions.
2. Tag the image with semantic versioning (e.g., `1.14.8-ansible-2.20.0`).
3. Authenticate and push to **GitHub Container Registry (GHCR)**.

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
