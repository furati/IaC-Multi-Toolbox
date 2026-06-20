#!/usr/bin/env sh
# ==========================================================================
# Single source of truth for tool version discovery.
#
#   ./scripts/discover-versions.sh            # print all as KEY=VALUE
#   ./scripts/discover-versions.sh terraform  # print just one version
#
# Used by the Makefile (local builds) and the GitHub workflows (CI/CD).
# Terraform/Packer/govc/tflint track the latest upstream release; apk-provided
# tools track whatever ALPINE_VERSION ships, keeping builds reproducible.
#
# Set GITHUB_TOKEN to avoid GitHub API rate limits in CI.
# ==========================================================================
set -eu

# Pinned Alpine release — the ONE place this is defined. Bump deliberately.
ALPINE_VERSION=3.22

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

apk_tool_version() {
  # $1 = apk package, $2 = command to print its version
  docker run --rm "alpine:${ALPINE_VERSION}" sh -c \
    "apk add --no-cache $1 >/dev/null && $2" \
    | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

tf_ver()     { docker run --rm hashicorp/terraform:latest version -json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
pk_ver()     { docker run --rm hashicorp/packer:latest version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
ans_ver()    { apk_tool_version ansible-core "ansible --version"; }
py_ver()     { apk_tool_version python3 "python3 --version"; }
al_ver()     { apk_tool_version ansible-lint "ansible-lint --version"; }
govc_ver()   { latest_tag vmware/govmomi; }                       # keeps leading "v"
tflint_ver() { latest_tag terraform-linters/tflint | sed 's/^v//'; }  # strips "v"

case "${1:-all}" in
  alpine)        echo "${ALPINE_VERSION}" ;;
  terraform)     tf_ver ;;
  packer)        pk_ver ;;
  ansible)       ans_ver ;;
  python)        py_ver ;;
  govc)          govc_ver ;;
  ansible-lint)  al_ver ;;
  tflint)        tflint_ver ;;
  all)
    echo "ALPINE_VERSION=${ALPINE_VERSION}"
    echo "TERRAFORM_VERSION=$(tf_ver)"
    echo "PACKER_VERSION=$(pk_ver)"
    echo "ANSIBLE_VERSION=$(ans_ver)"
    echo "PYTHON_VERSION=$(py_ver)"
    echo "GOVC_VERSION=$(govc_ver)"
    echo "TFLINT_VERSION=$(tflint_ver)"
    echo "ANSIBLE_LINT_VERSION=$(al_ver)"
    ;;
  tag)
    # Compute the image tag from versions already in the environment.
    # Run `discover-versions.sh all` and export the vars first.
    : "${TERRAFORM_VERSION:?run 'discover-versions.sh all' and export its output first}"
    echo "tf${TERRAFORM_VERSION}_pk${PACKER_VERSION}_ans${ANSIBLE_VERSION}_govc${GOVC_VERSION#v}_tflint${TFLINT_VERSION}_al${ANSIBLE_LINT_VERSION}_alpine${ALPINE_VERSION}"
    ;;
  *) echo "unknown tool: $1" >&2; exit 1 ;;
esac
