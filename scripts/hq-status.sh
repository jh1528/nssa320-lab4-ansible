#!/usr/bin/env bash
# ==============================================================================
# hq-status.sh
# ==============================================================================
#
# Headquarters status dashboard for NSSA320 Lab 4.
#
# Purpose:
#  - Show the current status of the RHEL control node as the lab headquarters
#  - Display Git branch/status, hostname, IP, routing, role resolution, and evidence status
#  - Include storage monitoring so logs and evidence archives do not grow unnoticed
#  - Provide a read-only operational snapshot before running bootstrap or validation scripts
#
# Design:
#  - This script does not change system configuration.
#  - It sources reusable libraries from config/ and lib/.
#  - It is intended to run from the control node.
#  - It helps verify that headquarters is ready to manage authorized lab targets.
#
# RICE Framework:
#  - Reproducibility: Runs the same headquarters checks each time.
#  - Idempotency: Read-only status checks do not alter state.
#  - Composability: Uses common, health, hosts, network, and evidence helpers.
#  - Evolvability: Additional headquarters checks can be added later.
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
#  - Added first headquarters status dashboard.
#  - Added Git branch and working tree status.
#  - Added hostname, network, and route overview.
#  - Added Lab 4 role resolution overview.
#  - Added evidence file and archive status.
#  - Added storage, memory, and CPU/load monitoring.
#
# Notes:
#  - This script is read-only.
#  - Evidence logs are small, but monitoring storage is still good practice.
#
# ==============================================================================

set -u


# ==============================================================================
# Path Setup
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EVIDENCE_DIR="${BASE_DIR}/evidence"
ARCHIVE_DIR="${EVIDENCE_DIR}/archive"
PING_LOG="${EVIDENCE_DIR}/ping.log"


# ==============================================================================
# Load Shared Configuration and Libraries
# ==============================================================================

source "${BASE_DIR}/config/lab4.conf"
source "${BASE_DIR}/lib/common.sh"
source "${BASE_DIR}/lib/health.sh"
source "${BASE_DIR}/lib/hosts.sh"
source "${BASE_DIR}/lib/network.sh"
source "${BASE_DIR}/lib/evidence.sh"


# ==============================================================================
# Usage
# ==============================================================================

usage() {
    cat <<EOF
Usage:
  $0

Options:
  -h, --help    Show this help message

Description:
  Shows a read-only headquarters status dashboard for the Lab 4 control node.

  Includes:
    - Git status
    - Hostname and network state
    - Lab role resolution
    - Evidence and archive status
    - Storage, memory, and CPU/load checks
EOF
}


# ==============================================================================
# Git Status
# ==============================================================================

show_git_status() {
    local branch_name

    step "Git source-of-truth status"

    if ! command -v git >/dev/null 2>&1; then
        warn "git command not found"
        return 1
    fi

    if ! git -C "$BASE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warn "Repository directory is not a Git working tree: ${BASE_DIR}"
        return 1
    fi

    branch_name="$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || printf '%s\n' 'unknown')"

    info "Repository: ${BASE_DIR}"
    info "Branch: ${branch_name}"

    if git -C "$BASE_DIR" diff --quiet && git -C "$BASE_DIR" diff --cached --quiet; then
        pass "Git working tree is clean"
    else
        warn "Git working tree has local changes"
        git -C "$BASE_DIR" status --short
    fi
}


# ==============================================================================
# Headquarters Identity
# ==============================================================================

show_hq_identity() {
    local expected_control_fqdn
    local current_hostname

    expected_control_fqdn="$(get_host_fqdn_for_role control)"
    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"

    step "Headquarters identity"

    info "Expected control hostname: ${expected_control_fqdn}"
    info "Current hostname: ${current_hostname}"

    if [[ "$current_hostname" == "$expected_control_fqdn" ]]; then
        pass "This node is named like the Lab 4 control node"
    else
        warn "This node hostname does not match the expected control node hostname"
    fi

    info "Current user: $(whoami)"
    info "Current date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}


# ==============================================================================
# Role Resolution Overview
# ==============================================================================

show_role_resolution_overview() {
    local roles=("control" "ansible1" "ansible2" "ubuntu")
    local role
    local role_ip
    local role_fqdn
    local resolved_line

    step "Lab 4 role resolution overview"

    printf '%-10s %-16s %-28s %-10s\n' "ROLE" "EXPECTED-IP" "FQDN" "STATUS"
    printf '%-10s %-16s %-28s %-10s\n' "----------" "----------------" "----------------------------" "----------"

    for role in "${roles[@]}"; do
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

    echo

    for role in "${roles[@]}" "$GATEWAY_HOST"; do
        if getent hosts "$role" >/dev/null 2>&1; then
            resolved_line="$(getent hosts "$role" | head -n 1)"
            pass "Resolved ${role}: ${resolved_line}"
        else
            fail "Could not resolve ${role}"
        fi
    done
}


# ==============================================================================
# Evidence Status
# ==============================================================================

show_evidence_status() {
    local archive_count
    local evidence_size
    local archive_size

    step "Evidence and archive status"

    mkdir -p "$EVIDENCE_DIR" "$ARCHIVE_DIR"

    show_evidence_location "$PING_LOG" "$ARCHIVE_DIR"

    archive_count="$(
        find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.log' 2>/dev/null | wc -l
    )"

    evidence_size="$(du -sh "$EVIDENCE_DIR" 2>/dev/null | awk '{print $1}')"
    archive_size="$(du -sh "$ARCHIVE_DIR" 2>/dev/null | awk '{print $1}')"

    info "Evidence directory size: ${evidence_size:-unknown}"
    info "Archive directory size: ${archive_size:-unknown}"
    info "Archived log count: ${archive_count}"

    if [[ -f "$PING_LOG" ]]; then
        pass "Current ping.log exists"
        ls -lh "$PING_LOG"
    else
        warn "Current ping.log does not exist yet"
    fi

    if [[ "$archive_count" -gt 20 ]]; then
        warn "Archive contains more than 20 log files. Consider reviewing old attempts later."
    else
        pass "Archive log count is reasonable"
    fi
}


# ==============================================================================
# Storage and System Health
# ==============================================================================

show_storage_monitor() {
    step "Storage monitor"

    info "Root filesystem usage:"
    df -h /

    check_disk "/" 80 90
    check_disk_free_gb "/" 5 2

    step "Evidence storage monitor"

    if [[ -d "$EVIDENCE_DIR" ]]; then
        du -sh "$EVIDENCE_DIR" "$ARCHIVE_DIR" 2>/dev/null || warn "Unable to calculate evidence directory sizes"
        pass "Evidence storage check completed"
    else
        warn "Evidence directory does not exist yet: ${EVIDENCE_DIR}"
    fi
}

show_system_health() {
    step "Basic system health"

    check_memory 80 95
    check_memory_total_gb 2 1
    check_cpu_load 2.00 4.00
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    step "Lab 4 headquarters status dashboard"

    info "HQ role: RHEL control node"
    info "Purpose: authorized lab automation and evidence coordination"

    show_git_status
    show_hq_identity
    show_network_state
    show_role_resolution_overview
    show_evidence_status
    show_storage_monitor
    show_system_health

    step "HQ status summary"

    pass "Headquarters status dashboard completed"
}

main "$@"
