#!/usr/bin/env bash
# ==============================================================================
# network.sh
# ==============================================================================
#
# Shared network configuration and validation helpers for Lab 4 Activity 1.
#
# Purpose:
#  - Map a Lab 4 role to the correct static IP address
#  - Detect the active NetworkManager connection
#  - Apply static IPv4 settings idempotently
#  - Validate IP address, default gateway, DNS configuration, and gateway reachability
#  - Display current network state for troubleshooting
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by scripts such as bootstrap-node.sh and health-check.sh.
#  - Network values are read from config/lab4.conf.
#  - Output is handled through lib/common.sh.
#
# RICE Framework:
#  - Reproducibility: Network state comes from one config file.
#  - Idempotency: Re-running applies the same static IP/gateway/DNS without duplication.
#  - Composability: Bootstrap and health scripts can reuse the same network functions.
#  - Evolvability: Subnet, gateway, DNS, and hosts can change in lab4.conf later.
#
# Dependencies:
#  - config/lab4.conf must be sourced before this file is used.
#  - lib/common.sh must be sourced before this file is used.
#  - lib/hosts.sh should be sourced before this file is used because it provides
#    get_host_ip_for_role.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 1.1
# Date: 2026-06-09
#
# Changes:
#  - Added active NetworkManager connection detection.
#  - Added role-based static IP configuration.
#  - Added IP, route, DNS, and gateway validation helpers.
#  - Added current network state display helper.
#
# Notes:
#  - This is the first Activity 1 version of the Lab 4 network management library.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB4_NETWORK_SH_LOADED:-}" ]]; then
    return 0
fi

LAB4_NETWORK_SH_LOADED="true"


# ==============================================================================
# NetworkManager Detection Helpers
# ==============================================================================

detect_active_nm_connection() {
    local connection

    if ! command -v nmcli >/dev/null 2>&1; then
        die "Required command not found: nmcli"
    fi

    connection="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: 'NR==1 {print $1}')"

    if [[ -z "$connection" ]]; then
        die "No active NetworkManager connection found."
    fi

    printf '%s\n' "$connection"
}

detect_active_nm_device() {
    local device

    if ! command -v nmcli >/dev/null 2>&1; then
        die "Required command not found: nmcli"
    fi

    device="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: 'NR==1 {print $2}')"

    if [[ -z "$device" ]]; then
        die "No active NetworkManager device found."
    fi

    printf '%s\n' "$device"
}


# ==============================================================================
# Network State Display
# ==============================================================================

show_network_state() {
    step "Current network state"

    info "Hostname:"
    hostname

    info "IPv4 addresses:"
    ip -4 -brief addr show || warn "Unable to show IPv4 addresses"

    info "Routing table:"
    ip route || warn "Unable to show routing table"

    info "Active NetworkManager connections:"
    nmcli con show --active || warn "Unable to show active NetworkManager connections"

    info "DNS configuration from NetworkManager:"
    nmcli dev show | grep -E 'IP4.DNS|GENERAL.DEVICE' || warn "Unable to show DNS configuration"
}


# ==============================================================================
# Static Network Configuration
# ==============================================================================

configure_network_for_role() {
    local role="$1"
    local expected_ip
    local connection
    local device

    expected_ip="$(get_host_ip_for_role "$role")"
    connection="$(detect_active_nm_connection)"
    device="$(detect_active_nm_device)"

    step "Configuring static network settings"

    info "Role: ${role}"
    info "Connection: ${connection}"
    info "Device: ${device}"
    info "Expected IP: ${expected_ip}/${SUBNET_PREFIX}"
    info "Gateway: ${GATEWAY_IP}"
    info "DNS servers: ${DNS_SERVERS}"

    nmcli con mod "$connection" ipv4.addresses "${expected_ip}/${SUBNET_PREFIX}" \
        || die "Failed to set IPv4 address on ${connection}"

    nmcli con mod "$connection" ipv4.gateway "$GATEWAY_IP" \
        || die "Failed to set IPv4 gateway on ${connection}"

    nmcli con mod "$connection" ipv4.dns "$DNS_SERVERS" \
        || die "Failed to set IPv4 DNS servers on ${connection}"

    nmcli con mod "$connection" ipv4.method manual \
        || die "Failed to set IPv4 method to manual on ${connection}"

    nmcli con mod "$connection" connection.autoconnect yes \
        || die "Failed to enable autoconnect on ${connection}"

    pass "Static IPv4 settings applied to ${connection}"

    info "Restarting NetworkManager connection ${connection}"

    nmcli con down "$connection" >/dev/null 2>&1 || warn "Connection ${connection} was not cleanly brought down"
    nmcli con up "$connection" || die "Failed to bring connection ${connection} back up"

    pass "Network connection restarted successfully"
}


# ==============================================================================
# Network Validation
# ==============================================================================

validate_ip_for_role() {
    local role="$1"
    local expected_ip

    expected_ip="$(get_host_ip_for_role "$role")"

    step "Validating IPv4 address"

    info "Expected IP: ${expected_ip}/${SUBNET_PREFIX}"

    if ip -4 addr show | grep -q "${expected_ip}/${SUBNET_PREFIX}"; then
        pass "Expected IP address is configured: ${expected_ip}/${SUBNET_PREFIX}"
        return 0
    else
        fail "Expected IP address not found: ${expected_ip}/${SUBNET_PREFIX}"
        info "Current IPv4 addresses:"
        ip -4 -brief addr show
        return 1
    fi
}

validate_default_gateway() {
    step "Validating default gateway"

    info "Expected default gateway: ${GATEWAY_IP}"

    if ip route | grep -q "default via ${GATEWAY_IP}"; then
        pass "Default gateway is configured: ${GATEWAY_IP}"
        return 0
    else
        fail "Default gateway is not configured as expected"
        info "Current routing table:"
        ip route
        return 1
    fi
}

validate_gateway_ping() {
    step "Validating gateway reachability"

    info "Pinging gateway: ${GATEWAY_IP}"

    if ping -c 3 "$GATEWAY_IP" >/tmp/lab4_gateway_ping.out 2>&1; then
        cat /tmp/lab4_gateway_ping.out
        pass "Gateway is reachable: ${GATEWAY_IP}"
        return 0
    else
        cat /tmp/lab4_gateway_ping.out
        fail "Gateway is not reachable: ${GATEWAY_IP}"
        return 1
    fi
}

validate_dns_resolution() {
    local dns_test_host="${1:-github.com}"

    step "Validating external DNS resolution"

    info "Test hostname: ${dns_test_host}"

    if getent hosts "$dns_test_host" >/tmp/lab4_dns_test.out 2>&1; then
        cat /tmp/lab4_dns_test.out
        pass "External DNS resolution works for ${dns_test_host}"
        return 0
    else
        fail "External DNS resolution failed for ${dns_test_host}"
        return 1
    fi
}

validate_network_for_role() {
    local role="$1"
    local failed=0

    step "Running full network validation for role: ${role}"

    validate_ip_for_role "$role" || failed=1
    validate_default_gateway || failed=1
    validate_gateway_ping || failed=1
    validate_dns_resolution "github.com" || failed=1

    if (( failed == 0 )); then
        pass "Network validation passed for role: ${role}"
        return 0
    else
        fail "Network validation failed for role: ${role}"
        return 1
    fi
}
