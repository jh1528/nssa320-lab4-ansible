#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Activity 2 Control Node Verification
# File: scripts/verify-control-node.sh
#
# Purpose:
#   Verifies the RHEL 8 control node after Activity 2 setup and produces
#   terminal output suitable for the required Figure 2 screenshot.
#
# Scope:
#   Activity 2 only.
#   This script is read-only and should not modify system configuration.
#
# Safety:
#   Does not install packages.
#   Does not update packages.
#   Does not register, unregister, refresh, or overwrite Red Hat licensing.
#   Does not configure managed hosts, SSH keys, Ansible users, or sudoers files.
#
# RICE Notes:
#   Reproducibility - runs the same verification checks each time.
#   Idempotency     - read-only validation with no system changes.
#   Composability   - uses shared config and library functions.
#   Evolvability    - can be extended for additional Activity 2 evidence checks.
#
# Version History:
#   v2.0 - Initial Activity 2 verification and evidence workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

source config/lab4.conf
source config/activity2.conf
source lib/common.sh
source lib/redhat.sh
source lib/packages.sh

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME
  $SCRIPT_NAME --help

Description:
  Runs read-only verification checks for Lab 4 Activity 2 and prints output
  suitable for the required screenshot:

    Figure 2 – Ansible Install Verification

The screenshot should visibly include:
  - hostname
  - date
  - ansible --version
  - domain/prompt context showing the control node identity

This script also writes a copy of the verification output to:
  ${ACTIVITY2_FIGURE2_OUTPUT}

EOF
}

run_verification() {
  mkdir -p "$ACTIVITY2_EVIDENCE_DIR"

  {
    step "Figure 2 - Ansible Install Verification"

    info "Activity: ${ACTIVITY2_NAME}"
    info "Activity version: ${ACTIVITY2_VERSION}"
    info "Expected control hostname: ${CONTROL_HOSTNAME:-control.jh1528.com}"
    info "Expected lab domain: ${LAB_DOMAIN:-jh1528.com}"

    step "Hostname verification"
    hostname
    hostname -f 2>/dev/null || true

    step "Date verification"
    date

    step "Ansible installation verification"
    ansible --version

    step "Python verification"
    python3 --version

    step "Package verification"
    rpm -q epel-release
    rpm -q ansible

    step "Red Hat subscription/content access verification"
    check_subscription_identity
    check_subscription_status

    step "Repository verification"
    check_codeready_builder_enabled
    check_deprecated_ansible_repo_not_enabled

    step "Activity 2 verification complete"
    pass "Figure 2 evidence output generated."
  } | tee "$ACTIVITY2_FIGURE2_OUTPUT"

  pass "Saved verification output to: ${ACTIVITY2_FIGURE2_OUTPUT}"
  info "Take a screenshot of this terminal and label it:"
  info "Figure 2 – Ansible Install Verification"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      ;;
    "")
      run_verification
      ;;
    *)
      fail "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
}

main "$@"
