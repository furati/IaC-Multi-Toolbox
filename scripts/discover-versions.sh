#!/usr/bin/env sh
# ==========================================================================
# Single source of truth for tool version discovery.
#
#   ./scripts/discover-versions.sh            # print all as KEY=VALUE
#   ./scripts/discover-versions.sh terraform  # print just one version
#
# Used by the Makefile (local builds) and the GitHub workflows (CI/CD).
# Terraform/Packer/govc/tflint track the latest upstream release,
# ansible-core/ansible-lint track the latest PyPI release, and the dind
# engine tracks whatever the pinned Debian release ships — keeping every
# build reproducible for a given set of discovered versions.
#
# Set GITHUB_TOKEN to avoid GitHub API rate limits in CI.
# ==========================================================================
set -eu

# Pinned Debian release — the ONE place this is defined. Bump deliberately.
DEBIAN_VERSION=13

gh_api() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$1"
  else
    curl -fsSL "$1"
  fi
}

latest_tag() {
  # $1 = owner/repo  ->  prints latest release tag (e.g. v0.54.1)
  gh_api "https://api.github.com/repos/$1/releases/latest" \
    | grep -oE '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+'
}

pypi_ver() {
  # $1 = PyPI package  ->  prints the latest release version
  curl -fsSL "https://pypi.org/pypi/$1/json" \
    | python3 -c 'import sys, json; print(json.load(sys.stdin)["info"]["version"])'
}

tf_ver()     { docker run --rm hashicorp/terraform:latest version -json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
pk_ver()     { docker run --rm hashicorp/packer:latest version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
ans_ver()    { pypi_ver ansible-core; }
al_ver()     { pypi_ver ansible-lint; }
govc_ver()   { latest_tag vmware/govmomi; }                       # keeps leading "v"
tflint_ver() { latest_tag terraform-linters/tflint | sed 's/^v//'; }  # strips "v"

# docker.io version shipped by the pinned Debian release (drives the dind tag).
docker_ver() {
  docker run --rm "debian:${DEBIAN_VERSION}-slim" sh -c \
    'apt-get update -qq >/dev/null 2>&1; apt-cache policy docker.io' \
    | sed -n 's/.*Candidate: *//p' | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+'
}

case "${1:-all}" in
  debian)        echo "${DEBIAN_VERSION}" ;;
  terraform)     tf_ver ;;
  packer)        pk_ver ;;
  ansible)       ans_ver ;;
  ansible-lint)  al_ver ;;
  govc)          govc_ver ;;
  tflint)        tflint_ver ;;
  docker)        docker_ver ;;
  all)
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}"
    echo "TERRAFORM_VERSION=$(tf_ver)"
    echo "PACKER_VERSION=$(pk_ver)"
    echo "ANSIBLE_VERSION=$(ans_ver)"
    echo "GOVC_VERSION=$(govc_ver)"
    echo "TFLINT_VERSION=$(tflint_ver)"
    echo "ANSIBLE_LINT_VERSION=$(al_ver)"
    ;;
  tag)
    # Compute the toolbox image tag from versions already in the environment.
    # Run `discover-versions.sh all` and export the vars first.
    : "${TERRAFORM_VERSION:?run 'discover-versions.sh all' and export its output first}"
    echo "tf${TERRAFORM_VERSION}_pk${PACKER_VERSION}_ans${ANSIBLE_VERSION}_govc${GOVC_VERSION#v}_tflint${TFLINT_VERSION}_al${ANSIBLE_LINT_VERSION}_deb${DEBIAN_VERSION}"
    ;;
  dind-tag)
    # Compute the dind image tag; DOCKER_VERSION must be in the environment
    # (from `discover-versions.sh docker`).
    : "${DOCKER_VERSION:?run 'DOCKER_VERSION=$(discover-versions.sh docker)' first}"
    echo "docker${DOCKER_VERSION}_deb${DEBIAN_VERSION}"
    ;;
  *) echo "unknown tool: $1" >&2; exit 1 ;;
esac
