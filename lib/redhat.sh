#!/usr/bin/env bash
# ==============================================================================
# redhat.sh
# ==============================================================================
#
# Shared Red Hat Enterprise Linux helper functions for Lab 4 automation scripts.
#
# Purpose:
#  - Check Red Hat release information.
#  - Check subscription-manager availability.
#  - Check Red Hat subscription identity and status safely.
#  - Check enabled repository information without triggering GUI authentication.
#  - Support Activity 2 control-node setup and verification workflows.
#
# Important:
#  - This library does not register systems.
#  - This library does not enable repositories by itself.
#  - setup-control-node.sh --apply is responsible for sudo-required setup work.
#  - verify-control-node.sh should run as the normal student user.
#
# RICE Notes:
#  - Reproducibility: standardizes Red Hat subscription and repository checks.
#  - Idempotency: checks current state without changing registration.
#  - Composability: reusable by Activity 2 setup and verification scripts.
#  - Evolvability: future Red Hat repository checks can be added here.
#
# Version History:
#  - v2.0 - Initial Red Hat subscription helper library for Activity 2.
#  - v2.1 - Added CodeReady Builder and deprecated Ansible Engine repo checks.
#  - v2.2 - Treat RIT/Satellite Organization/Environment content access as valid
#           even when subscription-manager reports Overall Status: Unknown.
#  - v2.3 - Prevent non-root verification from triggering GUI authentication
#           prompts by skipping privileged subscription-manager identity/status
#           checks and using dnf repolist for enabled repository checks.
#
# ==============================================================================


# ==============================================================================
# Safety guard
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "[FAIL] lib/redhat.sh is a shared library and should be sourced, not executed."
    echo "[INFO] Example: source lib/redhat.sh"
    exit 1
fi


# ==============================================================================
# Red Hat release checks
# ==============================================================================

check_rhel_release() {
    step "Checking Red Hat release information"

    if [[ ! -f /etc/redhat-release ]]; then
        fail "Red Hat release file not found."
        return 1
    fi

    pass "Red Hat release file found."
    info "$(cat /etc/redhat-release)"
    return 0
}

check_redhat_release() {
    check_rhel_release
}

check_redhat_release_info() {
    check_rhel_release
}


# ==============================================================================
# subscription-manager checks
# ==============================================================================

check_subscription_manager() {
    step "Checking subscription-manager availability"

    if command -v subscription-manager >/dev/null 2>&1; then
        pass "Required command found: subscription-manager"
        return 0
    fi

    fail "Required command not found: subscription-manager"
    warn "Install or repair subscription-manager before continuing Activity 2."
    return 1
}

check_subscription_manager_available() {
    check_subscription_manager
}

check_subscription_manager_availability() {
    check_subscription_manager
}

check_rhel_subscription_identity() {
    step "Checking Red Hat subscription identity"

    if [[ "${EUID}" -ne 0 ]]; then
        warn "Privileged subscription identity check skipped during non-root verification."
        info "This avoids GUI authentication prompts from subscription-manager."
        info "Run setup-control-node.sh --apply with sudo for privileged subscription checks."
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

check_subscription_identity() {
    check_rhel_subscription_identity
}

check_rhel_subscription_status() {
    local status_output
    local status_rc

    step "Checking Red Hat subscription/content access status"

    if [[ "${EUID}" -ne 0 ]]; then
        warn "Privileged subscription status check skipped during non-root verification."
        info "This avoids GUI authentication prompts from subscription-manager."
        info "Repository access will be verified with dnf repolist."
        return 0
    fi

    status_output="$(subscription-manager status 2>&1)"
    status_rc=$?

    if [[ "$status_rc" -eq 0 ]]; then
        pass "subscription-manager status completed successfully."
        return 0
    fi

    if grep -qi "Overall Status: Unknown" <<< "$status_output"; then
        warn "subscription-manager reports Overall Status: Unknown."
        warn "This can be normal in RIT/Satellite Organization/Environment access."
        info "Repository access will be verified separately."
        return 0
    fi

    if grep -qi "Simple Content Access" <<< "$status_output"; then
        warn "subscription-manager returned non-zero, but Simple Content Access appears to be enabled."
        info "Repository access will be verified separately."
        return 0
    fi

    fail "subscription-manager status reported a problem."
    info "$status_output"
    return 1
}

check_subscription_status() {
    check_rhel_subscription_status
}


# ==============================================================================
# Repository checks
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
    return 1
}

check_deprecated_repo_keyword_absent() {
    local repo_keyword="$1"
    local repos_output

    if [[ -z "$repo_keyword" ]]; then
        die "Usage: check_deprecated_repo_keyword_absent <repo_keyword>"
    fi

    step "Checking deprecated repository keyword is absent: ${repo_keyword}"

    repos_output="$(get_enabled_repos_output || true)"

    if grep -qi "$repo_keyword" <<< "$repos_output"; then
        fail "Deprecated repository keyword found in enabled repositories: ${repo_keyword}"
        warn "Disable deprecated Red Hat Ansible Engine repositories for Activity 2."
        return 1
    fi

    pass "Deprecated repository keyword not found: ${repo_keyword}"
    return 0
}

check_deprecated_repo_absent() {
    check_deprecated_repo_keyword_absent "$@"
}
