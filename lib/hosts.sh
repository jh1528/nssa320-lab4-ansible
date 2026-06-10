#!/usr/bin/env bash
# ==============================================================================
# hosts.sh
# ==============================================================================
#
# Shared hostname and /etc/hosts helpers for Lab 4 Activity 1.
#
# Purpose:
#  - Map a Lab 4 role to the correct hostname, FQDN, and IP address
#  - Set the system hostname idempotently
#  - Manage the Lab 4 /etc/hosts block idempotently
#  - Validate local hostname and short-name resolution
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by scripts such as bootstrap-node.sh and health-check.sh.
#  - Host data is read from config/lab4.conf.
#  - Output is handled through lib/common.sh.
#
# RICE Framework:
#  - Reproducibility: Hostname and /etc/hosts values come from one config file.
#  - Idempotency: Existing managed /etc/hosts block is replaced, not duplicated.
#  - Composability: Bootstrap and health scripts can reuse the same host functions.
#  - Evolvability: New hosts can be added later by updating config and role mapping.
#
# Dependencies:
#  - config/lab4.conf must be sourced before this file is used.
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
# Date: 2026-06-09
#
# Changes:
#  - Added role-to-hostname mapping helpers.
#  - Added idempotent hostname setter.
#  - Added idempotent /etc/hosts managed block writer.
#  - Added hostname and /etc/hosts validation helpers.
#
# Notes:
#  - This is the first Activity 1 version of the Lab 4 host management library.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================
#
# Purpose:
#  - Prevent this file from being loaded more than once in the same shell session.
# ==============================================================================

if [[ -n "${LAB4_HOSTS_SH_LOADED:-}" ]]; then
    return 0
fi

LAB4_HOSTS_SH_LOADED="true"


# ==============================================================================
# Role Mapping Helpers
# ==============================================================================

get_host_short_for_role() {
    local role="$1"

    case "$role" in
        control)
            printf '%s\n' "$CONTROL_HOST"
            ;;
        ansible1)
            printf '%s\n' "$ANSIBLE1_HOST"
            ;;
        ansible2)
            printf '%s\n' "$ANSIBLE2_HOST"
            ;;
        ubuntu)
            printf '%s\n' "$UBUNTU_HOST"
            ;;
        *)
            die "Unknown role '${role}'. Valid roles: control, ansible1, ansible2, ubuntu"
            ;;
    esac
}

get_host_ip_for_role() {
    local role="$1"

    case "$role" in
        control)
            printf '%s\n' "$CONTROL_IP"
            ;;
        ansible1)
            printf '%s\n' "$ANSIBLE1_IP"
            ;;
        ansible2)
            printf '%s\n' "$ANSIBLE2_IP"
            ;;
        ubuntu)
            printf '%s\n' "$UBUNTU_IP"
            ;;
        *)
            die "Unknown role '${role}'. Valid roles: control, ansible1, ansible2, ubuntu"
            ;;
    esac
}

get_host_fqdn_for_role() {
    local role="$1"
    local short_name

    short_name="$(get_host_short_for_role "$role")"
    printf '%s.%s\n' "$short_name" "$DOMAIN"
}


# ==============================================================================
# Hostname Management
# ==============================================================================

set_hostname_for_role() {
    local role="$1"
    local expected_fqdn
    local current_hostname

    expected_fqdn="$(get_host_fqdn_for_role "$role")"
    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"

    step "Configuring system hostname"

    info "Role: ${role}"
    info "Expected hostname: ${expected_fqdn}"
    info "Current hostname: ${current_hostname}"

    if [[ "$current_hostname" == "$expected_fqdn" ]]; then
        pass "Hostname already set correctly: ${expected_fqdn}"
        return 0
    fi

    info "Setting hostname to ${expected_fqdn}"
    hostnamectl set-hostname "$expected_fqdn" || die "Failed to set hostname to ${expected_fqdn}"

    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"

    if [[ "$current_hostname" == "$expected_fqdn" ]]; then
        pass "Hostname successfully set to ${expected_fqdn}"
        return 0
    else
        die "Hostname validation failed. Expected ${expected_fqdn}, found ${current_hostname}"
    fi
}

validate_hostname_for_role() {
    local role="$1"
    local expected_fqdn
    local current_hostname

    expected_fqdn="$(get_host_fqdn_for_role "$role")"
    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"

    step "Validating system hostname"

    info "Expected hostname: ${expected_fqdn}"
    info "Current hostname: ${current_hostname}"

    if [[ "$current_hostname" == "$expected_fqdn" ]]; then
        pass "Hostname validation passed"
        return 0
    else
        fail "Hostname validation failed"
        return 1
    fi
}


# ==============================================================================
# /etc/hosts Management
# ==============================================================================

backup_hosts_file() {
    local backup_file

    backup_file="/etc/hosts.bak.$(date +%Y%m%d-%H%M%S)"

    info "Backing up /etc/hosts to ${backup_file}"
    cp /etc/hosts "$backup_file" || die "Failed to back up /etc/hosts"

    pass "Backup created: ${backup_file}"
}

write_lab_hosts_block() {
    step "Writing Lab 4 managed block to /etc/hosts"

    backup_hosts_file

    info "Removing existing Lab 4 managed block if present"

    sed -i '/# BEGIN NSSA320 LAB4 HOSTS/,/# END NSSA320 LAB4 HOSTS/d' /etc/hosts \
        || die "Failed to remove existing Lab 4 hosts block"

    info "Appending refreshed Lab 4 hosts block"

    cat >> /etc/hosts <<EOF

# BEGIN NSSA320 LAB4 HOSTS
# Managed by Lab 4 Activity 1 bootstrap scripts.
# Do not manually edit inside this block unless you also update config/lab4.conf.
${CONTROL_IP}  ${CONTROL_FQDN}   ${CONTROL_HOST}
${ANSIBLE1_IP} ${ANSIBLE1_FQDN}  ${ANSIBLE1_HOST}
${ANSIBLE2_IP} ${ANSIBLE2_FQDN}  ${ANSIBLE2_HOST}
${UBUNTU_IP}   ${UBUNTU_FQDN}    ${UBUNTU_HOST}
${GATEWAY_IP}  ${GATEWAY_FQDN}   ${GATEWAY_HOST}
# END NSSA320 LAB4 HOSTS
EOF

    pass "Lab 4 /etc/hosts block written"
}

validate_hosts_resolution() {
    local failed=0
    local host

    step "Validating local host resolution"

    for host in "$CONTROL_HOST" "$ANSIBLE1_HOST" "$ANSIBLE2_HOST" "$UBUNTU_HOST" "$GATEWAY_HOST"; do
        info "Resolving ${host}"

        if getent hosts "$host" >/dev/null 2>&1; then
            pass "Resolved ${host}: $(getent hosts "$host" | head -n 1)"
        else
            fail "Could not resolve ${host}"
            failed=1
        fi
    done

    if (( failed == 0 )); then
        pass "All Lab 4 short hostnames resolved successfully"
        return 0
    else
        fail "One or more Lab 4 hostnames failed to resolve"
        return 1
    fi
}

show_lab_hosts_block() {
    step "Displaying Lab 4 /etc/hosts managed block"

    if grep -q '# BEGIN NSSA320 LAB4 HOSTS' /etc/hosts; then
        sed -n '/# BEGIN NSSA320 LAB4 HOSTS/,/# END NSSA320 LAB4 HOSTS/p' /etc/hosts
        return 0
    else
        warn "Lab 4 managed hosts block was not found in /etc/hosts"
        return 1
    fi
}
