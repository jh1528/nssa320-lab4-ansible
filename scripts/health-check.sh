#!/usr/bin/env bash
# ==============================================================================
# health-check.sh
# ==============================================================================
#
# Read-only Activity 1 health-check script for NSSA320 Lab 4.
#
# Purpose:
#  - Validate that a Lab 4 node is in a healthy Activity 1 state
#  - Check host identity, /etc/hosts resolution, network state, SSH status,
#    and basic system readiness
#  - Support checking one role or displaying all role expectations
#  - Provide PASS/WARN/FAIL output using the shared common.sh helpers
#
# Design:
#  - This script does not change system configuration.
#  - It sources reusable libraries from config/ and lib/.
#  - It accepts one Lab 4 role as an argument:
#      control
#      ansible1
#      ansible2
#      ubuntu
#      all
#
# RICE Framework:
#  - Reproducibility: Runs the same validation process every time.
#  - Idempotency: Read-only checks do not alter system state.
#  - Composability: Combines common, health, hosts, network, and SSH libraries.
#  - Evolvability: New checks can be added without rewriting helper libraries.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 1.1
# Date: 2026-06-10
#
# Changes:
#  - Added support for the all argument.
#  - Added all-role host-resolution summary.
#  - Added per-role expected IP/FQDN display.
#  - Kept deep system validation focused on the local/current node.
#
# Notes:
#  - Deep checks such as local hostname, local IP, SSH service status, memory,
#    disk, and CPU are only meaningful for the VM where this script is running.
#  - The all mode summarizes role definitions and host resolution for every role.
#
# ==============================================================================

set -u


# ==============================================================================
# Path Setup
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"


# ==============================================================================
# Load Shared Configuration and Libraries
# ==============================================================================

source "${BASE_DIR}/config/lab4.conf"
source "${BASE_DIR}/lib/common.sh"
source "${BASE_DIR}/lib/health.sh"
source "${BASE_DIR}/lib/hosts.sh"
source "${BASE_DIR}/lib/network.sh"
source "${BASE_DIR}/lib/ssh.sh"


# ==============================================================================
# Globals
# ==============================================================================

LAB4_ROLES=("control" "ansible1" "ansible2" "ubuntu")


# ==============================================================================
# Usage and Argument Handling
# ==============================================================================

usage() {
    cat <<EOF
Usage:
  $0 <role>

Roles:
  control
  ansible1
  ansible2
  ubuntu
  all

Examples:
  $0 control
  $0 ansible1
  $0 ubuntu
  $0 all

Description:
  Runs read-only Activity 1 health checks for the selected Lab 4 node.

  The all mode shows all Lab 4 role definitions and validates local hostname
  resolution for each role. Deep local checks only apply to the current VM.
EOF
}

validate_role_argument() {
    local role="$1"

    case "$role" in
        control|ansible1|ansible2|ubuntu|all)
            return 0
            ;;
        *)
            fail "Invalid role: ${role}"
            usage
            exit 2
            ;;
    esac
}


# ==============================================================================
# All-Role Summary Helpers
# ==============================================================================

show_all_role_expectations() {
    local role
    local role_fqdn
    local role_ip

    step "Lab 4 role expectations"

    printf '%-10s %-16s %-28s %-10s\n' "ROLE" "IP" "FQDN" "RESOLUTION"
    printf '%-10s %-16s %-28s %-10s\n' "----------" "----------------" "----------------------------" "----------"

    for role in "${LAB4_ROLES[@]}"; do
        role_ip="$(get_host_ip_for_role "$role")"
        role_fqdn="$(get_host_fqdn_for_role "$role")"

        if getent hosts "$role" >/dev/null 2>&1; then
            printf '%-10s %-16s %-28s PASS\n' "$role" "$role_ip" "$role_fqdn"
        else
            printf '%-10s %-16s %-28s FAIL\n' "$role" "$role_ip" "$role_fqdn"
        fi
    done

    if getent hosts "$GATEWAY_HOST" >/dev/null 2>&1; then
        printf '%-10s %-16s %-28s PASS\n' "$GATEWAY_HOST" "$GATEWAY_IP" "$GATEWAY_FQDN"
    else
        printf '%-10s %-16s %-28s FAIL\n' "$GATEWAY_HOST" "$GATEWAY_IP" "$GATEWAY_FQDN"
    fi
}

validate_all_role_resolution() {
    local failed=0
    local role

    step "Validating all Lab 4 role name resolution"

    for role in "${LAB4_ROLES[@]}"; do
        if getent hosts "$role" >/dev/null 2>&1; then
            pass "Resolved ${role}: $(getent hosts "$role" | head -n 1)"
        else
            fail "Could not resolve ${role}"
            failed=1
        fi
    done

    if getent hosts "$GATEWAY_HOST" >/dev/null 2>&1; then
        pass "Resolved ${GATEWAY_HOST}: $(getent hosts "$GATEWAY_HOST" | head -n 1)"
    else
        fail "Could not resolve ${GATEWAY_HOST}"
        failed=1
    fi

    return "$failed"
}

run_all_mode() {
    local failed=0

    step "Starting Lab 4 Activity 1 all-role health overview"

    info "Repository base directory: ${BASE_DIR}"
    info "Mode: all"

    show_all_role_expectations
    validate_all_role_resolution || failed=1

    step "All-role overview summary"

    if [[ "$failed" -eq 0 ]]; then
        pass "All Lab 4 roles resolve successfully from this node"
        return 0
    else
        fail "One or more Lab 4 roles failed to resolve from this node"
        return 1
    fi
}


# ==============================================================================
# Single-Role Deep Health Check Logic
# ==============================================================================

run_single_role_health_check() {
    local role="$1"
    local failed=0
    local warned=0
    local status=0

    step "Starting Lab 4 Activity 1 health check"

    info "Repository base directory: ${BASE_DIR}"
    info "Selected role: ${role}"
    info "Expected FQDN: $(get_host_fqdn_for_role "$role")"
    info "Expected IP: $(get_host_ip_for_role "$role")/${SUBNET_PREFIX}"
    info "Expected gateway: ${GATEWAY_IP}"

    step "Checking required local commands"

    require_command hostname
    require_command hostnamectl
    require_command getent
    require_command ip
    require_command ping
    require_command systemctl

    if command -v nmcli >/dev/null 2>&1; then
        pass "Required command found: nmcli"
    else
        fail "Required command not found: nmcli"
        failed=1
    fi

    step "Showing current network state"
    show_network_state || warned=1

    validate_hostname_for_role "$role" || failed=1
    validate_hosts_resolution || failed=1
    validate_ip_for_role "$role" || failed=1
    validate_default_gateway || failed=1
    validate_gateway_ping || failed=1
    validate_dns_resolution "github.com" || warned=1
    validate_ssh_service || failed=1

    step "Checking basic system readiness"

    check_disk "/" 80 90
    status=$?
    if [[ "$status" -eq 1 ]]; then
        warned=1
    elif [[ "$status" -ne 0 ]]; then
        failed=1
    fi

    check_disk_free_gb "/" 5 2
    status=$?
    if [[ "$status" -eq 1 ]]; then
        warned=1
    elif [[ "$status" -ne 0 ]]; then
        failed=1
    fi

    check_memory 80 95
    status=$?
    if [[ "$status" -eq 1 ]]; then
        warned=1
    elif [[ "$status" -ne 0 ]]; then
        failed=1
    fi

    check_memory_total_gb 2 1
    status=$?
    if [[ "$status" -eq 1 ]]; then
        warned=1
    elif [[ "$status" -ne 0 ]]; then
        failed=1
    fi

    check_cpu_load 2.00 4.00
    status=$?
    if [[ "$status" -eq 1 ]]; then
        warned=1
    elif [[ "$status" -ne 0 ]]; then
        failed=1
    fi

    step "Health check summary"

    if [[ "$failed" -eq 0 && "$warned" -eq 0 ]]; then
        pass "Activity 1 health check passed with no warnings for role: ${role}"
        return 0
    elif [[ "$failed" -eq 0 && "$warned" -eq 1 ]]; then
        warn "Activity 1 health check passed with warnings for role: ${role}"
        return 0
    else
        fail "Activity 1 health check failed for role: ${role}"
        return 1
    fi
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    local role="${1:-}"

    if [[ -z "$role" ]]; then
        usage
        exit 2
    fi

    validate_role_argument "$role"

    if [[ "$role" == "all" ]]; then
        run_all_mode
        exit $?
    else
        run_single_role_health_check "$role"
        exit $?
    fi
}

main "$@"
