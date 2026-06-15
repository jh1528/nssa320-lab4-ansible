#!/usr/bin/env bash
# ==============================================================================
# ssh.sh
# ==============================================================================
#
# Shared SSH helpers for Lab 4.
#
# Purpose:
#  - Detect the Linux distribution family
#  - Determine the correct SSH service name
#  - Install OpenSSH server when needed on Ubuntu/Debian systems
#  - Enable and start the SSH service
#  - Validate SSH service status
#  - Show Activity 1 evidence commands for Ubuntu SSH verification
#  - Support Activity 3 SSH access checks and SSH key deployment
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by scripts such as bootstrap-node.sh,
#    health-check.sh, setup-managed-hosts.sh, and verify-managed-hosts.sh.
#  - Output is handled through lib/common.sh.
#  - SSH service configuration is kept separate from Ansible user creation.
#  - Activity 3 helpers do not configure sudoers or passwordless sudo.
#
# RICE Framework:
#  - Reproducibility: SSH readiness and access checks are performed consistently.
#  - Idempotency: Re-running enable/start commands and key checks is safe.
#  - Composability: Bootstrap, health, setup, and verification scripts can reuse SSH functions.
#  - Evolvability: Activity 4 privilege escalation can be added separately later.
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
# Version: 1.1
# Date: 2026-06-14
#
# Changes:
#  - Added Activity 3 SSH access helper functions.
#  - Added local SSH key existence/generation helper.
#  - Added ssh-copy-id helper for managed hosts.
#  - Added BatchMode-based key authentication verification helper.
#  - Confirmed this file does not configure Activity 4 passwordless sudo.
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
#  - Version 1.1 extends SSH support for Activity 3 managed-host access.
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


# ==============================================================================
# Activity 3 SSH Access Helpers
# ==============================================================================

activity3_verify_basic_ssh_access() {
    local remote_user="$1"
    shift

    local host

    if [[ -z "$remote_user" || "$#" -eq 0 ]]; then
        die "Usage: activity3_verify_basic_ssh_access <remote_user> <host> [host...]"
    fi

    step "Verifying basic SSH access"

    info "Remote user: ${remote_user}"
    info "This check allows first-time host key prompts and password prompts."

    for host in "$@"; do
        info "Testing SSH access to ${remote_user}@${host}"

        ssh \
            -o ConnectTimeout=10 \
            "${remote_user}@${host}" \
            'echo "remote hostname: $(hostname)"; echo "remote user: $(whoami)"; echo "remote date: $(date)"' \
            || die "Basic SSH access failed for ${remote_user}@${host}"

        pass "Basic SSH access succeeded: ${remote_user}@${host}"
    done
}

activity3_ensure_local_ssh_key() {
    local private_key_path="$1"
    local public_key_path="$2"

    if [[ -z "$private_key_path" || -z "$public_key_path" ]]; then
        die "Usage: activity3_ensure_local_ssh_key <private_key_path> <public_key_path>"
    fi

    step "Checking local SSH key"

    if [[ -f "$private_key_path" && -f "$public_key_path" ]]; then
        pass "Existing SSH key pair found: ${private_key_path}"
        info "Reusing existing SSH key pair."
        return 0
    fi

    if [[ -f "$private_key_path" && ! -f "$public_key_path" ]]; then
        die "Private key exists but public key is missing: ${public_key_path}"
    fi

    if [[ ! -f "$private_key_path" && -f "$public_key_path" ]]; then
        die "Public key exists but private key is missing: ${private_key_path}"
    fi

    info "No SSH key pair found at: ${private_key_path}"
    info "Generating a new SSH key pair with an empty passphrase for lab automation."

    mkdir -p "$(dirname "$private_key_path")" || die "Failed to create SSH directory"
    chmod 700 "$(dirname "$private_key_path")" || die "Failed to set SSH directory permissions"

    ssh-keygen -t rsa -b 4096 -f "$private_key_path" -N "" \
        || die "Failed to generate SSH key pair"

    pass "SSH key pair generated: ${private_key_path}"
}

activity3_copy_ssh_key_to_managed_hosts() {
    local remote_user="$1"
    shift

    local host

    if [[ -z "$remote_user" || "$#" -eq 0 ]]; then
        die "Usage: activity3_copy_ssh_key_to_managed_hosts <remote_user> <host> [host...]"
    fi

    step "Copying SSH public key to managed hosts"

    info "Remote user: ${remote_user}"
    info "You may be prompted for the ${remote_user} password on each host."

    for host in "$@"; do
        info "Copying SSH key to ${remote_user}@${host}"

        ssh-copy-id "${remote_user}@${host}" \
            || die "Failed to copy SSH key to ${remote_user}@${host}"

        pass "SSH key copied or already present: ${remote_user}@${host}"
    done
}

activity3_verify_key_based_ssh_access() {
    local remote_user="$1"
    shift

    local host

    if [[ -z "$remote_user" || "$#" -eq 0 ]]; then
        die "Usage: activity3_verify_key_based_ssh_access <remote_user> <host> [host...]"
    fi

    step "Verifying key-based SSH access"

    info "Remote user: ${remote_user}"
    info "BatchMode=yes prevents password prompts. Failure means key-based SSH is not ready."

    for host in "$@"; do
        info "Testing key-based SSH access to ${remote_user}@${host}"

        ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            "${remote_user}@${host}" \
            'echo "remote hostname: $(hostname)"; echo "remote user: $(whoami)"; echo "remote date: $(date)"' \
            || die "Key-based SSH access failed for ${remote_user}@${host}"

        pass "Key-based SSH access succeeded: ${remote_user}@${host}"
    done
}
