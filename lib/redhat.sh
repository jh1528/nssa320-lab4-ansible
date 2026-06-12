#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Red Hat Subscription Library
# File: lib/redhat.sh
#
# Purpose:
#   Provides reusable Red Hat subscription and repository helper functions
#   for Lab 4 Activity 2 workflows.
#
# Scope:
#   This library is designed for Activity 2 control-node preparation.
#   It checks Red Hat release information, subscription-manager availability,
#   registration identity, subscription status, and enabled repositories.
#
# Safety:
#   This file should be sourced by scripts, not executed directly.
#   It does not register, unregister, overwrite, or refresh Red Hat licensing.
#   It does not store Red Hat credentials, passwords, tokens, or secrets.
#
# RICE Notes:
#   Reproducibility - standardizes Red Hat subscription and repository checks.
#   Idempotency     - checks current state without changing registration.
#   Composability   - reusable by Activity 2 setup and verification scripts.
#   Evolvability    - future Red Hat repository checks can be added here.
#
# Version History:
#   v2.0 - Initial Red Hat subscription helper library for Activity 2.

# ---------------------------------------------------------------------------
# Safety guard
# ---------------------------------------------------------------------------

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
  step "Checking Red Hat subscription status"

  if subscription-manager status; then
    pass "subscription-manager status completed successfully."
    return 0
  fi

  fail "subscription-manager status reported a problem."
  warn "The system may be registered but not fully subscribed."
  warn "Check redhat.rit.edu and confirm the system is properly subscribed."
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

check_enabled_repo_keyword() {
  local repo_keyword="$1"

  step "Checking for enabled repository keyword: ${repo_keyword}"

  if subscription-manager repos --list-enabled 2>/dev/null | grep -qi "$repo_keyword"; then
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

  step "Checking deprecated Ansible Engine repository is not enabled"

  if subscription-manager repos --list-enabled 2>/dev/null | grep -qi "$repo_keyword"; then
    fail "Deprecated Ansible Engine repository appears to be enabled: ${repo_keyword}"
    warn "The lab says not to enable Red Hat Ansible Engine 2 for RHEL 8."
    return 1
  fi

  pass "Deprecated Ansible Engine repository keyword not found: ${repo_keyword}"
}
