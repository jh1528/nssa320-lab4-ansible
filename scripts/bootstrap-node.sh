#!/usr/bin/env bash
# ==============================================================================
# bootstrap-node.sh
# ==============================================================================
#
# Activity 1 bootstrap script for NSSA320 Lab 4.
#
# Purpose:
#  - Configure a Lab 4 VM to match its assigned role
#  - Set the correct system hostname
#  - Write the Lab 4 managed /etc/hosts block
#  - Apply static network settings from config/lab4.conf
#  - Install/enable/start OpenSSH server service when needed
#  - Run validation after configuration
#
# Design:
#  - This is an apply/configuration script.
#  - It supports --dry-run and --apply modes.
#  - It sources reusable libraries from config/ and lib/.
#  - Package changes are intentionally minimal:
#      - OpenSSH server may be installed if missing.
#      - Full dnf/yum/apt system updates are not performed here.
#      - pip is not used here.
#
# Supported Roles:
#  - control
#  - ansible1
#  - ansible2
#  - ubuntu
#
# RICE Framework:
#  - Reproducibility: Role configuration comes from config/lab4.conf.
#  - Idempotency: Re-running should converge on the same hostname, hosts file,
#    network settings, and SSH service state.
#  - Composability: Uses common, hosts, network, and SSH helper libraries.
#  - Evolvability: Later activities can add user, key, sudo, and Ansible setup
#    without rewriting Activity 1 bootstrap logic.
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
#  - Added first Activity 1 bootstrap runner.
#  - Added --dry-run and --apply modes.
#  - Added role validation.
#  - Added hostname, /etc/hosts, network, and SSH bootstrap workflow.
#  - Added post-bootstrap validation summary.
#
# Notes:
#  - This script intentionally does not run full OS updates.
#  - This script intentionally does not configure Ansible users, SSH keys, or sudo.
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
source "${BASE_DIR}/lib/hosts.sh"
source "${BASE_DIR}/lib/network.sh"
source "${BASE_DIR}/lib/ssh.sh"


# ==============================================================================
# Usage and Argument Handling
# ==============================================================================

usage() {
    cat <<EOF
Usage:
  $0 <role> <mode>

Roles:
  control
  ansible1
  ansible2
  ubuntu

Modes:
  --dry-run   Show what would be configured, but do not change the system
  --apply     Apply hostname, /etc/hosts, network, and SSH configuration

Examples:
  sudo $0 control --dry-run
  sudo $0 control --apply
  sudo $0 ansible1 --apply
  sudo $0 ubuntu --apply

Description:
  Bootstraps a Lab 4 VM for Activity 1.

  This script configures the node identity, local host records, static network
  settings, and SSH service readiness for the selected role.

Important:
  Run --dry-run first.
  Use --apply only when the selected role matches the VM you are configuring.
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

validate_mode_argument() {
    local mode="$1"

    case "$mode" in
        --dry-run|--apply)
            return 0
            ;;
        *)
            fail "Invalid mode: ${mode}"
            usage
            exit 2
            ;;
    esac
}


# ==============================================================================
# Dry Run
# ==============================================================================

dry_run_bootstrap() {
    local role="$1"
    local expected_fqdn
    local expected_ip

    expected_fqdn="$(get_host_fqdn_for_role "$role")"
    expected_ip="$(get_host_ip_for_role "$role")"

    step "Dry run: Activity 1 bootstrap plan"

    info "No changes will be made in dry-run mode."
    info "Selected role: ${role}"
    info "Expected hostname: ${expected_fqdn}"
    info "Expected IP address: ${expected_ip}/${SUBNET_PREFIX}"
    info "Expected gateway: ${GATEWAY_IP}"
    info "Expected DNS servers: ${DNS_SERVERS}"

    step "Actions that would be performed"

    info "Would set system hostname to: ${expected_fqdn}"
    info "Would write Lab 4 managed /etc/hosts block"
    info "Would configure static IPv4 settings through NetworkManager"
    info "Would install OpenSSH server if missing"
    info "Would enable and start SSH service"
    info "Would validate hostname, hosts resolution, IP, gateway, DNS, and SSH"

    step "Current state preview"

    info "Current hostname:"
    hostname

    info "Current IPv4 addresses:"
    ip -4 -brief addr show || warn "Unable to show IPv4 addresses"

    info "Current default route:"
    ip route | grep '^default' || warn "No default route found"

    if command -v nmcli >/dev/null 2>&1; then
        info "Active NetworkManager connections:"
        nmcli con show --active
    else
        warn "nmcli is not available"
    fi

    pass "Dry run completed for role: ${role}"
}


# ==============================================================================
# Apply Workflow
# ==============================================================================

apply_bootstrap() {
    local role="$1"
    local failed=0

    step "Starting Activity 1 bootstrap apply"

    info "Selected role: ${role}"
    info "Expected hostname: $(get_host_fqdn_for_role "$role")"
    info "Expected IP: $(get_host_ip_for_role "$role")/${SUBNET_PREFIX}"
    info "Expected gateway: ${GATEWAY_IP}"

    require_root

    step "Checking required commands"

    require_command hostname
    require_command hostnamectl
    require_command getent
    require_command ip
    require_command ping
    require_command systemctl
    require_command nmcli

    step "Applying host identity"

    set_hostname_for_role "$role" || failed=1
    write_lab_hosts_block || failed=1
    show_lab_hosts_block || failed=1
    validate_hostname_for_role "$role" || failed=1
    validate_hosts_resolution || failed=1

    step "Applying network configuration"

    configure_network_for_role "$role" || failed=1
    validate_network_for_role "$role" || failed=1

    step "Applying SSH service readiness"

    configure_ssh_for_activity1 || failed=1
    validate_ssh_service || failed=1

    step "Final Activity 1 bootstrap summary"

    if [[ "$failed" -eq 0 ]]; then
        pass "Activity 1 bootstrap completed successfully for role: ${role}"
        return 0
    else
        fail "Activity 1 bootstrap completed with failures for role: ${role}"
        return 1
    fi
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    local role="${1:-}"
    local mode="${2:-}"

    if [[ -z "$role" || -z "$mode" ]]; then
        usage
        exit 2
    fi

    validate_role_argument "$role"
    validate_mode_argument "$mode"

    case "$mode" in
        --dry-run)
            dry_run_bootstrap "$role"
            ;;
        --apply)
            apply_bootstrap "$role"
            ;;
    esac
}

main "$@"
