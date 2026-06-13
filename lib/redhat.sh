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
#  - Support Activity 2 control-node setup and verification workflows
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
# Version: v2.0
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
# Version: v2.1
# Date: 2026-06-12
#
# Changes:
#  - Prevented non-root verification from triggering GUI authentication prompts.
#  - Updated subscription identity and status checks to skip privileged
#    subscription-manager actions when verify-control-node.sh runs as student.
#  - Preserved privileged subscription-manager checks for root/setup workflows.
#  - Updated enabled repository checks to use dnf repolist --enabled.
#
# Notes:
#  - verify-control-node.sh should remain non-root.
#  - setup-control-node.sh --apply is still responsible for sudo-required setup.
#  - v2.2 remains reserved for idempotent evidence archiving.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB4_REDHAT_SH_LOADED:-}" ]]; then
    return 0
fi

LAB4_REDHAT_SH_LOADED="true"
LAB4_REDHAT_VERSION="v2.1"


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
# subscription-manager Checks
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

check_subscription_manager_availability() {
    check_subscription_manager_available
}

check_subscription_identity() {
    step "Checking Red Hat subscription identity"

    if [[ "${EUID}" -ne 0 ]]; then
        warn "Privileged subscription identity check skipped in non-root verification mode."
        info "This avoids GUI authentication prompts during verify-control-node.sh."
        info "Run setup-control-node.sh --apply with sudo for subscription registration checks."
        return 0
    fi

    if subscription-manager identity >/dev/null 2>&1; then
        pass "System has a Red Hat subscription identity."
        return 0
    fi

    fail "System does not appear to have a Red Hat subscription identity."
    warn "Register the system through redhat.rit.edu before continuing Activity 2."
    return 1
}

check_subscription_status() {
    local status_output
    local rc

    step "Checking Red Hat subscription/content access status"

    if [[ "${EUID}" -ne 0 ]]; then
        warn "Privileged subscription status check skipped in non-root verification mode."
        info "This avoids GUI authentication prompts during verify-control-node.sh."
        info "Repository access will be verified with dnf repolist."
        return 0
    fi

    status_output="$(subscription-manager status 2>&1)"
    rc=$?

    if [[ "$rc" -eq 0 ]]; then
        pass "subscription-manager status completed successfully."
        return 0
    fi

    if grep -qi "Overall Status: Unknown" <<< "$status_output"; then
        warn "subscription-manager reported Overall Status: Unknown."
        warn "This can be normal with Simple Content Access environments."
        info "Continuing because repository access will be verified separately."
        return 0
    fi

    if grep -qi "Simple Content Access" <<< "$status_output"; then
        warn "subscription-manager returned non-zero, but Simple Content Access appears to be enabled."
        info "Continuing because repository access will be verified separately."
        return 0
    fi

    fail "subscription-manager status reported a problem."
    info "$status_output"
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

show_enabled_repos() {
    list_enabled_repos
}

get_enabled_repos_output() {
    if ! command -v dnf >/dev/null 2>&1; then
        return 1
    fi

    dnf repolist --enabled 2>/dev/null
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
