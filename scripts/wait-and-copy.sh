#!/usr/bin/env bash
# ==============================================================================
# wait-and-copy.sh
# ==============================================================================
#
# Authorized Lab 4 helper script.
#
# Purpose:
#  - Wait for a Lab 4 managed node to become reachable
#  - Ping the target at a safe interval
#  - Copy the current repository from the control node to the target using scp
#
# Design:
#  - This script is for authorized lab administration only.
#  - It only accepts known Lab 4 roles from config/lab4.conf.
#  - It does not hide activity.
#  - It does not install persistence.
#  - It does not bypass authentication.
#  - scp may prompt for the remote user's password.
#
# RICE Framework:
#  - Reproducibility: Uses known Lab 4 role names and repository path.
#  - Idempotency: Copying the repo repeatedly refreshes the same destination.
#  - Composability: Uses shared common and host helper libraries.
#  - Evolvability: Can later be replaced by Ansible once Activity 3 is complete.
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
#  - Added wait-and-copy helper for managed node bootstrap workflow.
#  - Added role validation.
#  - Added configurable interval and max attempts.
#  - Added dry-run and copy modes.
#  - Added scp transfer from control node to managed node.
#
# Notes:
#  - This is a temporary pre-Ansible helper.
#  - Once Ansible is configured, Ansible should replace this workflow.
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


# ==============================================================================
# Defaults
# ==============================================================================

REMOTE_USER="${LAB_USER:-student}"
INTERVAL_SECONDS=300
MAX_ATTEMPTS=12
MODE="--dry-run"


# ==============================================================================
# Usage
# ==============================================================================

usage() {
    cat <<EOF
Usage:
  $0 <role> <mode> [options]

Roles:
  ansible1
  ansible2
  ubuntu

Modes:
  --dry-run       Show what would happen, but do not copy files
  --copy          Wait for target and copy repository with scp

Options:
  --user USER             Remote SSH/SCP user. Default: ${REMOTE_USER}
  --interval SECONDS      Seconds between ping attempts. Default: ${INTERVAL_SECONDS}
  --max-attempts NUMBER   Maximum ping attempts. Default: ${MAX_ATTEMPTS}
  -h, --help              Show this help message

Examples:
  $0 ansible1 --dry-run
  $0 ansible1 --copy
  $0 ansible1 --copy --interval 300 --max-attempts 12
  $0 ubuntu --copy --user student

Description:
  This script runs from the control node. It waits for a managed Lab 4 node
  to reply to ping, then copies the current repo to that node using scp.

Important:
  This is a temporary pre-Ansible helper.
  It is for authorized Lab 4 nodes only.
EOF
}


# ==============================================================================
# Argument Validation
# ==============================================================================

validate_role_argument() {
    local role="$1"

    case "$role" in
        ansible1|ansible2|ubuntu)
            return 0
            ;;
        control)
            die "Do not use wait-and-copy for control. This script copies from control to managed nodes."
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
        --dry-run|--copy)
            return 0
            ;;
        *)
            fail "Invalid mode: ${mode}"
            usage
            exit 2
            ;;
    esac
}

parse_arguments() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    TARGET_ROLE="${1:-}"
    MODE="${2:-}"

    if [[ -z "$TARGET_ROLE" || -z "$MODE" ]]; then
        usage
        exit 2
    fi

    validate_role_argument "$TARGET_ROLE"
    validate_mode_argument "$MODE"

    shift 2

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --user)
                REMOTE_USER="${2:-}"
                shift 2
                ;;
            --interval)
                INTERVAL_SECONDS="${2:-}"
                shift 2
                ;;
            --max-attempts)
                MAX_ATTEMPTS="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    if [[ -z "$REMOTE_USER" ]]; then
        die "Remote user cannot be empty."
    fi

    if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]]; then
        die "Interval must be a positive integer."
    fi

    if ! [[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]]; then
        die "Max attempts must be a positive integer."
    fi

    if [[ "$INTERVAL_SECONDS" -lt 1 ]]; then
        die "Interval must be at least 1 second."
    fi

    if [[ "$MAX_ATTEMPTS" -lt 1 ]]; then
        die "Max attempts must be at least 1."
    fi
}


# ==============================================================================
# Target Checks
# ==============================================================================

show_plan() {
    local target_ip
    local target_fqdn

    target_ip="$(get_host_ip_for_role "$TARGET_ROLE")"
    target_fqdn="$(get_host_fqdn_for_role "$TARGET_ROLE")"

    step "Wait-and-copy plan"

    info "Mode: ${MODE}"
    info "Target role: ${TARGET_ROLE}"
    info "Target IP: ${target_ip}"
    info "Target FQDN: ${target_fqdn}"
    info "Remote user: ${REMOTE_USER}"
    info "Source repo: ${BASE_DIR}"
    info "Remote destination: ${REMOTE_USER}@${TARGET_ROLE}:/home/${REMOTE_USER}/"
    info "Ping interval: ${INTERVAL_SECONDS} seconds"
    info "Max attempts: ${MAX_ATTEMPTS}"
}

wait_for_target_ping() {
    local attempt=1

    step "Waiting for target to become reachable"

    while [[ "$attempt" -le "$MAX_ATTEMPTS" ]]; do
        info "Attempt ${attempt}/${MAX_ATTEMPTS}: ping ${TARGET_ROLE}"

        if ping -c 2 -W 2 "$TARGET_ROLE" >/dev/null 2>&1; then
            pass "Target is reachable: ${TARGET_ROLE}"
            return 0
        fi

        warn "Target not reachable yet: ${TARGET_ROLE}"

        if [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; then
            info "Sleeping ${INTERVAL_SECONDS} seconds before next attempt..."
            sleep "$INTERVAL_SECONDS"
        fi

        attempt=$(( attempt + 1 ))
    done

    fail "Target did not become reachable after ${MAX_ATTEMPTS} attempts: ${TARGET_ROLE}"
    return 1
}

copy_repo_to_target() {
    step "Copying repository to target with scp"

    info "Source: ${BASE_DIR}"
    info "Destination: ${REMOTE_USER}@${TARGET_ROLE}:/home/${REMOTE_USER}/"

    scp -r "$BASE_DIR" "${REMOTE_USER}@${TARGET_ROLE}:/home/${REMOTE_USER}/" \
        || die "scp transfer failed for target: ${TARGET_ROLE}"

    pass "Repository copied successfully to ${TARGET_ROLE}"
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    parse_arguments "$@"

    step "Authorized Lab 4 wait-and-copy helper"

    warn "This script is for authorized Lab 4 administration only."
    warn "It does not bypass authentication. scp may prompt for a password."

    require_command ping
    require_command scp

    show_plan

    if [[ "$MODE" == "--dry-run" ]]; then
        pass "Dry run complete. No files copied."
        exit 0
    fi

    wait_for_target_ping || exit 1
    copy_repo_to_target

    step "Next step on target"

    info "SSH into the target:"
    info "  ssh ${REMOTE_USER}@${TARGET_ROLE}"
    info "Then run:"
    info "  cd $(basename "$BASE_DIR")"
    info "  sudo ./scripts/bootstrap-node.sh ${TARGET_ROLE} --dry-run"
    info "  sudo ./scripts/bootstrap-node.sh ${TARGET_ROLE} --apply"

    pass "wait-and-copy completed for ${TARGET_ROLE}"
}

main "$@"
