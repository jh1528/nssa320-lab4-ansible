#!/usr/bin/env bash
# ==============================================================================
# redhat.sh
# ==============================================================================
#
# Shared Red Hat Enterprise Linux helper functions for Lab 4 automation scripts.
#
# Purpose:
#  - Check Red Hat release information
#  - Check subscription-manager availability
#  - Check Red Hat subscription identity and status safely
#  - Check enabled repository information without triggering GUI authentication
#  - Support Activity 2 control-node verification and setup workflows
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by setup and verification scripts.
#  - Output is handled through lib/common.sh.
#  - Verification should remain non-root and should not trigger GUI auth prompts.
#
# RICE Framework:
#  - Reproducibility: Red Hat checks produce predictable PASS/WARN/FAIL output.
#  - Idempotency: Checks do not change system state.
#  - Composability: Setup and verify scripts can reuse shared helper functions.
#  - Evolvability: Repository and subscription checks can be extended later.
#
# Dependencies:
#  - lib/common.sh must be sourced before this file is used.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 1.0
# Date: 2026-06-10
#
# Changes:
#  - Added Red Hat release checks.
#  - Added subscription-manager availability checks.
#  - Added subscription identity and status checks.
#  - Added enabled repository keyword checks.
#
# ------------------------------------------------------------------------------
#
# Version: 1.1
# Date: 2026-06-12
#
# Changes:
#  - Prevented non-root verification from triggering GUI authentication prompts.
#  - Added non-interactive subscription-manager helper using sudo -n.
#  - Updated enabled repository checks to use dnf repolist instead of
#    subscription-manager repos --list-enabled.
#  - Preserved Activity 2 verification behavior while keeping evidence files
#    owned by the student user.
#
# Notes:
#  - setup-control-node.sh may still be run with sudo when applying system changes.
#  - verify-control-node.sh should run as the normal student user.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB4_REDHAT_SH_LOADED:-}" ]]; then
    return 0
fi

LAB4_REDHAT_SH_LOADED="true"
LAB4_REDHAT_VERSION="v1.1"


# ==============================================================================
# Red Hat Release Checks
# ==============================================================================

check_redhat_release() {
    step "Checking Red Hat release information"

    if [[ ! -f /etc/redhat-release ]]; then
        fail "Red Hat release file was not found."
        warn "This host does not appear to be a Red Hat Enterprise Linux system."
        return 1
    fi

    pass "Red Hat release file found."
    info "$(cat /etc/redhat-release)"
    return 0
}

check_redhat_release_info() {
    check_redhat_release
}


# ==============================================================================
# subscription-manager Helpers
# ==============================================================================

check_subscription_manager_available() {
    step "Checking subscription-manager availability"

    if ! command -v subscription-manager >/dev/null 2>&1; then
        fail "Required command not found: subscription-manager"
        warn "Install or repair subscription-manager before continuing Activity 2."
        return 1
    fi

    pass "Required command found: subscription-manager"
    return 0
}

run_subscription_manager_noninteractive() {
    local output_file="$1"
    shift

    if [[ -z "$output_file" || "$#" -eq 0 ]]; then
        die "Usage: run_subscription_manager_noninteractive <output_file> <subscription-manager arguments...>"
    fi

    : > "$output_file" || die "Could not write temporary output file: ${output_file}"

    if [[ "${EUID}" -eq 0 ]]; then
        subscription-manager "$@" >"$output_file" 2>&1
        return $?
    fi

    if sudo -n true >/dev/null 2>&1; then
        sudo -n subscription-manager "$@" >"$output_file" 2>&1
        return $?
    fi

    {
        echo "Non-interactive sudo authentication is not available."
        echo "Skipping privileged subscription-manager check to avoid GUI authentication prompts."
    } >"$output_file"

    return 2
}

check_subscription_identity() {
    local identity_output
    local rc

    step "Checking Red Hat subscription identity"

    identity_output="$(mktemp)"
    run_subscription_manager_noninteractive "$identity_output" identity
    rc=$?

    if [[ "$rc" -eq 0 ]]; then
        pass "System has a Red Hat subscription identity."
        rm -f "$identity_output"
        return 0
    fi

    if [[ "$rc" -eq 2 ]]; then
        warn "Subscription identity check skipped in non-root verification mode."
        info "Reason: $(tr '\n' ' ' < "$identity_output")"
        info "Run setup-control-node.sh --apply with sudo for privileged subscription checks."
        rm -f "$identity_output"
        return 0
    fi

    fail "System does not appear to have a Red Hat subscription identity."
    warn "Register the system through redhat.rit.edu before continuing Activity 2."
    info "$(tr '\n' ' ' < "$identity_output")"
    rm -f "$identity_output"
    return 1
}

check_subscription_status() {
    local status_output
    local rc

    step "Checking Red Hat subscription/content access status"

    status_output="$(mktemp)"
    run_subscription_manager_noninteractive "$status_output" status
    rc=$?

    if [[ "$rc" -eq 0 ]]; then
        pass "subscription-manager status completed successfully."
        rm -f "$status_output"
        return 0
    fi

    if grep -qi "Overall Status: Unknown" "$status_output"; then
        warn "subscription-manager reported Overall Status: Unknown."
        warn "This can be normal with Simple Content Access environments."
        info "Continuing because repository access will be verified separately."
        rm -f "$status_output"
        return 0
    fi

    if grep -qi "Simple Content Access" "$status_output"; then
        warn "subscription-manager returned non-zero, but Simple Content Access appears to be enabled."
        info "Continuing because repository access will be verified separately."
        rm -f "$status_output"
        return 0
    fi

    if [[ "$rc" -eq 2 ]]; then
        warn "Subscription status check skipped in non-root verification mode."
        info "Reason: $(tr '\n' ' ' < "$status_output")"
        info "Repository access will be verified with dnf repolist."
        rm -f "$status_output"
        return 0
    fi

    fail "subscription-manager status reported a problem."
    info "$(tr '\n' ' ' < "$status_output")"
    rm -f "$status_output"
    return 1
}


# ==============================================================================
# Repository Checks
# ==============================================================================

list_enabled_repos() {
    step "Listing enabled repositories"

    if ! command -v dnf >/dev/null 2>&1; then
        fail "Required command not found: dnf"
        return 1
    fi

    if dnf repolist --enabled; then
        pass "Enabled repository list displayed successfully."
        return 0
    fi

    fail "Could not list enabled repositories with dnf."
    warn "Repository access may not be fully configured."
    return 1
}

get_enabled_repos_output() {
    if command -v dnf >/dev/null 2>&1; then
        dnf repolist --enabled 2>/dev/null
        return $?
    fi

    return 1
}

check_enabled_repo_keyword() {
    local repo_keyword="$1"
    local repos_output

    if [[ -z "$repo_keyword" ]]; then
        die "Usage: check_enabled_repo_keyword <repo_keyword>"
    fi

    step "Checking for enabled repository keyword: ${repo_keyword}"

    repos_output="$(get_enabled_repos_output || true)"

    if grep -qi "$repo_keyword" <<< "$repos_output"; then
        pass "Repository keyword found in enabled repositories: ${repo_keyword}"
        return 0
    fi

    fail "Repository keyword not found in enabled repositories: ${repo_keyword}"
    warn "CodeReady Builder does not appear to be enabled."
    warn "Enable Red Hat CodeReady Linux Builder for RHEL 8 x86_64 through redhat.rit.edu."
    return 1
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "[FAIL] lib/redhat.sh is a shared library and should be sourced, not executed."
  echo "[INFO] Example: source lib/redhat.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# Red Hat release checks
# ---------------------------------------------------------------------------

check_rhel_release() {
  step "Checking Red Hat release information"

  if [[ ! -r /etc/redhat-release ]]; then
    fail "/etc/redhat-release was not found."
    warn "This does not appear to be a RHEL-family system."
    return 1
  fi

  pass "Red Hat release file found."
  info "$(cat /etc/redhat-release)"
}

# ---------------------------------------------------------------------------
# subscription-manager checks
# ---------------------------------------------------------------------------

check_subscription_manager_available() {
  step "Checking subscription-manager availability"

  if ! command -v subscription-manager >/dev/null 2>&1; then
    fail "Required command not found: subscription-manager"
    warn "Install or repair subscription-manager before continuing Activity 2."
    return 1
  fi

  pass "Required command found: subscription-manager"
}

check_subscription_identity() {
  step "Checking Red Hat subscription identity"

  if subscription-manager identity >/dev/null 2>&1; then
    pass "System has a Red Hat subscription identity."
    subscription-manager identity
    return 0
  fi

  fail "System does not appear to have a Red Hat subscription identity."
  warn "Register manually through redhat.rit.edu before continuing Activity 2."
  warn "No registration changes were made."
  return 1
}

check_subscription_status() {
  step "Checking Red Hat subscription/content access status"

  local status_output
  local status_rc

  set +e
  status_output="$(subscription-manager status 2>&1)"
  status_rc=$?
  set -e

  printf '%s\n' "$status_output"

  if [[ "$status_rc" -eq 0 ]]; then
    pass "subscription-manager status completed successfully."
    return 0
  fi

  if grep -qi "This host has access to content" <<< "$status_output"; then
    warn "subscription-manager status returned non-zero, but content access is available."
    warn "Overall Status may appear as Unknown in the RIT/Satellite environment."
    pass "Red Hat content access appears usable for Activity 2."
    return 0
  fi

  fail "subscription-manager status reported a problem."
  warn "The system may be registered but may not have usable content access."
  warn "Check redhat.rit.edu and confirm the system is properly registered/subscribed."
  return 1
}

# ---------------------------------------------------------------------------
# Repository checks
# ---------------------------------------------------------------------------

list_enabled_repos() {
  step "Listing enabled Red Hat repositories"

  if subscription-manager repos --list-enabled; then
    pass "Enabled repository list displayed successfully."
    return 0
  fi

  fail "Could not list enabled repositories."
  warn "Registration may exist, but repository access may not be fully configured."
  return 1
}

get_enabled_repos_output() {
  subscription-manager repos --list-enabled 2>/dev/null
}

check_enabled_repo_keyword() {
  local repo_keyword="$1"
  local repos_output

  step "Checking for enabled repository keyword: ${repo_keyword}"

  repos_output="$(get_enabled_repos_output || true)"

  if grep -qi "$repo_keyword" <<< "$repos_output"; then
    pass "Repository keyword found in enabled repositories: ${repo_keyword}"
    return 0
  fi

  fail "Repository keyword not found in enabled repositories: ${repo_keyword}"
  return 1
}

check_codeready_builder_enabled() {
  local repo_keyword="${ACTIVITY2_REQUIRED_REPO_KEYWORD:-codeready-builder}"

  step "Checking CodeReady Builder repository"

  if check_enabled_repo_keyword "$repo_keyword"; then
    pass "CodeReady Builder appears to be enabled."
    return 0
  fi

  warn "CodeReady Builder does not appear to be enabled."
  warn "Enable Red Hat CodeReady Linux Builder for RHEL 8 x86_64 through redhat.rit.edu."
  return 1
}

check_deprecated_ansible_repo_not_enabled() {
  local repo_keyword="${ACTIVITY2_DEPRECATED_REPO_KEYWORD:-ansible-2}"
  local repos_output

  step "Checking deprecated Ansible Engine repository is not enabled"

  repos_output="$(get_enabled_repos_output || true)"

  if grep -qi "$repo_keyword" <<< "$repos_output"; then
    fail "Deprecated Ansible Engine repository appears to be enabled: ${repo_keyword}"
    warn "The lab says not to enable Red Hat Ansible Engine 2 for RHEL 8."
    return 1
  fi

  pass "Deprecated Ansible Engine repository keyword not found: ${repo_keyword}"
}
