#!/usr/bin/env bash
# ==============================================================================
# ssh.sh
# ==============================================================================
#
# Shared SSH service helpers for Lab 4 Activity 1.
#
# Purpose:
#  - Detect the Linux distribution family
#  - Determine the correct SSH service name
#  - Install OpenSSH server when needed on Ubuntu/Debian systems
#  - Enable and start the SSH service
#  - Validate SSH service status
#  - Show Activity 1 evidence commands for Ubuntu SSH verification
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by scripts such as bootstrap-node.sh and health-check.sh.
#  - Output is handled through lib/common.sh.
#  - SSH service configuration is kept separate from SSH key automation.
#
# RICE Framework:
#  - Reproducibility: SSH readiness is checked the same way on every node.
#  - Idempotency: Re-running enable/start commands is safe.
#  - Composability: Bootstrap and health scripts can reuse SSH functions.
#  - Evolvability: SSH key and Ansible user logic can be added later in Activity 3.
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
# Date: 2026-06-09
#
# Changes:
#  - Added OS family detection.
#  - Added SSH service-name detection.
#  - Added OpenSSH server installation helper for Ubuntu/Debian.
#  - Added SSH enable/start/status validation helpers.
#  - Added Ubuntu Activity 1 evidence display helper.
#
# Notes:
#  - This is the first Activity 1 version of the Lab 4 SSH management library.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB4_SSH_SH_LOADED:-}" ]]; then
    return 0
fi

LAB4_SSH_SH_LOADED="true"


# ==============================================================================
# OS Detection Helpers
# ==============================================================================

get_os_id() {
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf '%s\n' "${ID:-unknown}"
    else
        printf '%s\n' "unknown"
    fi
}

get_os_family() {
    local os_id

    os_id="$(get_os_id)"

    case "$os_id" in
        rhel|rocky|centos|fedora)
            printf '%s\n' "redhat"
            ;;
        ubuntu|debian)
            printf '%s\n' "debian"
            ;;
        *)
            printf '%s\n' "unknown"
            ;;
    esac
}

get_ssh_service_name() {
    local os_family

    os_family="$(get_os_family)"

    case "$os_family" in
        redhat)
            printf '%s\n' "sshd"
            ;;
        debian)
            printf '%s\n' "ssh"
            ;;
        *)
            die "Unable to determine SSH service name for OS family: ${os_family}"
            ;;
    esac
}


# ==============================================================================
# SSH Installation Helpers
# ==============================================================================

install_openssh_server_if_needed() {
    local os_family

    os_family="$(get_os_family)"

    step "Checking OpenSSH server package"

    case "$os_family" in
        redhat)
            if rpm -q openssh-server >/dev/null 2>&1; then
                pass "OpenSSH server package is installed"
            else
                info "Installing OpenSSH server package with dnf"
                dnf install -y openssh-server || die "Failed to install openssh-server"
                pass "OpenSSH server package installed"
            fi
            ;;
        debian)
            if dpkg -s openssh-server >/dev/null 2>&1; then
                pass "OpenSSH server package is installed"
            else
                info "Updating apt package index"
                apt-get update || die "Failed to update apt package index"

                info "Installing OpenSSH server package with apt"
                apt-get install -y openssh-server || die "Failed to install openssh-server"

                pass "OpenSSH server package installed"
            fi
            ;;
        *)
            die "Unsupported OS family for OpenSSH installation: ${os_family}"
            ;;
    esac
}


# ==============================================================================
# SSH Service Management
# ==============================================================================

enable_start_ssh_service() {
    local service_name

    service_name="$(get_ssh_service_name)"

    step "Enabling and starting SSH service"

    info "SSH service name: ${service_name}"

    systemctl enable --now "$service_name" || die "Failed to enable/start ${service_name}"

    pass "SSH service enabled and started: ${service_name}"
}

validate_ssh_service() {
    local service_name

    service_name="$(get_ssh_service_name)"

    step "Validating SSH service"

    info "SSH service name: ${service_name}"

    if systemctl is-enabled "$service_name" >/dev/null 2>&1; then
        pass "SSH service is enabled: ${service_name}"
    else
        fail "SSH service is not enabled: ${service_name}"
        return 1
    fi

    if systemctl is-active "$service_name" >/dev/null 2>&1; then
        pass "SSH service is active: ${service_name}"
        return 0
    else
        fail "SSH service is not active: ${service_name}"
        return 1
    fi
}

show_ssh_status() {
    local service_name

    service_name="$(get_ssh_service_name)"

    step "Showing SSH service status"

    systemctl status "$service_name" --no-pager
}

configure_ssh_for_activity1() {
    step "Configuring SSH for Activity 1"

    install_openssh_server_if_needed
    enable_start_ssh_service
    validate_ssh_service
}

show_ubuntu_ssh_evidence() {
    local os_id

    os_id="$(get_os_id)"

    step "Ubuntu SSH evidence commands"

    if [[ "$os_id" != "ubuntu" ]]; then
        warn "This evidence helper is intended for the Ubuntu node."
        info "Current OS ID: ${os_id}"
    fi

    systemctl status ssh --no-pager
    date
    hostname
}
