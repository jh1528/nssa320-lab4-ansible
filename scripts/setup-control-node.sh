#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Activity 2 Control Node Setup
# File: scripts/setup-control-node.sh
#
# Purpose:
#   Prepares the RHEL 8 control node for Ansible by validating subscription
#   readiness, updating the system, installing EPEL, and installing Ansible.
#
# Scope:
#   Activity 2 only.
#   This script prepares the control node only.
#
# Safety:
#   Supports --dry-run and --apply modes.
#   Does not register, unregister, refresh, or overwrite Red Hat licensing.
#   Does not configure managed hosts, SSH keys, Ansible users, or sudoers files.
#
# RICE Notes:
#   Reproducibility - runs the same Activity 2 setup sequence each time.
#   Idempotency     - checks package state before installing when possible.
#   Composability   - uses shared config and library functions.
#   Evolvability    - can be extended for additional Activity 2 checks.
#
# Version History:
#   v2.0 - Initial Activity 2 control-node setup workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Source shared configuration and libraries
# ---------------------------------------------------------------------------

source config/lab4.conf
source config/activity2.conf
source lib/common.sh
source lib/redhat.sh
source lib/packages.sh

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --apply
  $SCRIPT_NAME --help

Description:
  Prepares the RHEL 8 control node for Ansible as required by Lab 4 Activity 2.

Modes:
  --dry-run   Show what would be checked or changed, but do not install/update.
  --apply     Apply Activity 2 setup steps.

Activity 2 actions:
  1. Check RHEL release.
  2. Check subscription-manager availability.
  3. Check Red Hat subscription identity.
  4. Check Red Hat subscription status.
  5. Check CodeReady Builder repository.
  6. Confirm deprecated Ansible Engine 2 repository is not enabled.
  7. Run dnf update -y.
  8. Install EPEL if missing.
  9. Install required Activity 2 packages.

This script does not register Red Hat licensing, store credentials,
configure managed hosts, create Ansible users, deploy SSH keys, or configure sudo.

EOF
}

dry_run() {
  step "Activity 2 dry run starting"

  info "Repository root: ${REPO_ROOT}"
  info "Activity version: ${ACTIVITY2_VERSION}"
  info "Activity name: ${ACTIVITY2_NAME}"

  check_rhel_release
  check_subscription_manager_available
  check_subscription_identity
  check_subscription_status
  check_codeready_builder_enabled
  check_deprecated_ansible_repo_not_enabled

  step "Dry-run package plan"

  info "Would run: dnf update -y"
  info "Would ensure EPEL package is installed: ${ACTIVITY2_EPEL_PACKAGE}"
  info "Would install EPEL from: ${ACTIVITY2_EPEL_RPM_URL}"

  local package_name
  for package_name in "${ACTIVITY2_REQUIRED_PACKAGES[@]}"; do
    if rpm -q "$package_name" >/dev/null 2>&1; then
      pass "Package already installed: ${package_name}"
    else
      warn "Would install missing package: ${package_name}"
    fi
  done

  step "Activity 2 dry run complete"
  pass "No changes were made."
}

apply_setup() {
  step "Activity 2 apply starting"

  require_root

  check_rhel_release
  check_subscription_manager_available
  check_subscription_identity
  check_subscription_status
  check_codeready_builder_enabled
  check_deprecated_ansible_repo_not_enabled

  dnf_update_system
  install_epel_if_missing
  install_required_packages

  step "Activity 2 setup verification"

  show_ansible_version
  show_python_version
  show_dnf_repolist

  step "Activity 2 apply complete"
  pass "Control node package setup completed."
}

main() {
  case "${1:-}" in
    --dry-run)
      dry_run
      ;;
    --apply)
      apply_setup
      ;;
    -h|--help)
      usage
      ;;
    "")
      fail "Missing required mode."
      usage
      exit 2
      ;;
    *)
      fail "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
}

main "$@"
