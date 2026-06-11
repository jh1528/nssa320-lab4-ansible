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
# Version: 1.0
# Date: 2026-06-10
#
# Changes:
#  - Added first read-only Activity 1 health-check runner.
#  - Added role argument validation.
#  - Added host, network, SSH, disk, memory, and CPU/load checks.
#  - Added final health summary with exit status.
#
# Notes:
#  - This script should be safe to run repeatedly.
#  - Use bootstrap-node.sh later for configuration/apply actions.
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

Examples:
  $0 control
  $0 ansible1
  $0 ubuntu

Description:
  Runs read-only Activity 1 health checks for the selected Lab 4 node.
EOF
}

validate_role_argument() {
    local role="$1"

    case "$role" in
        control|ansible1|ansible2|ubuntu)
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
# Main Health Check Logic
# ==============================================================================

main() {
    local role="${1:-}"
    local failed=0
    local warned=0

    if [[ -z "$role" ]]; then
        usage
        exit 2
    fi

    validate_role_argument "$role"

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

    check_disk "/" 80 90 || {
        status=$?
        if [[ "$status" -eq 1 ]]; then
            warned=1
        else
            failed=1
        fi
    }

    check_disk_free_gb "/" 5 2 || {
        status=$?
        if [[ "$status" -eq 1 ]]; then
            warned=1
        else
            failed=1
        fi
    }

    check_memory 80 95 || {
        status=$?
        if [[ "$status" -eq 1 ]]; then
            warned=1
        else
            failed=1
        fi
    }

    check_memory_total_gb 2 1 || {
        status=$?
        if [[ "$status" -eq 1 ]]; then
            warned=1
        else
            failed=1
        fi
    }

    check_cpu_load 2.00 4.00 || {
        status=$?
        if [[ "$status" -eq 1 ]]; then
            warned=1
        else
            failed=1
        fi
    }

    step "Health check summary"

    if [[ "$failed" -eq 0 && "$warned" -eq 0 ]]; then
        pass "Activity 1 health check passed with no warnings for role: ${role}"
        exit 0
    elif [[ "$failed" -eq 0 && "$warned" -eq 1 ]]; then
        warn "Activity 1 health check passed with warnings for role: ${role}"
        exit 0
    else
        fail "Activity 1 health check failed for role: ${role}"
        exit 1
    fi
}


main "$@"
