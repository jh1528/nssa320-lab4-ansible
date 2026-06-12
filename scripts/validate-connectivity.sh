#!/usr/bin/env bash
# ==============================================================================
# validate-connectivity.sh
# ==============================================================================
#
# Activity 1 connectivity validation script for NSSA320 Lab 4.
#
# Purpose:
#  - Generate the Activity 1 professor-facing evidence file: evidence/ping.log
#  - Validate that the control node can ping required Lab 4 targets
#  - Preserve previous ping.log attempts using lib/evidence.sh
#  - Provide clear PASS/FAIL terminal output using lib/common.sh
#
# Design:
#  - This script is evidence-focused.
#  - It should be run from the Ansible control node.
#  - It does not configure network settings.
#  - It does not overwrite old ping.log files without archiving them first.
#  - Evidence/archive behavior is handled by lib/evidence.sh.
#
# RICE Framework:
#  - Reproducibility: Uses ping targets from config/lab4.conf.
#  - Idempotency: Re-running archives the previous ping.log instead of destroying it.
#  - Composability: Uses shared common, hosts, network, and evidence helpers.
#  - Evolvability: Additional evidence types or targets can be added later.
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
#  - Added first Activity 1 connectivity validation runner.
#  - Added professor-facing ping.log generation.
#  - Added evidence archive integration through lib/evidence.sh.
#  - Added control-node safety check.
#  - Added target PASS/FAIL summary.
#
# Notes:
#  - The final evidence file is always evidence/ping.log.
#  - Previous attempts are stored in evidence/archive/.
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
  Generates the Activity 1 connectivity evidence file:

    evidence/ping.log

  If evidence/ping.log already exists, it is moved to:

    evidence/archive/

  This script should be run from the Lab 4 control node.
EOF
}


# ==============================================================================
# Control Node Safety Check
# ==============================================================================

validate_running_on_control_node() {
    local expected_fqdn
    local current_hostname

    expected_fqdn="$(get_host_fqdn_for_role control)"
    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"

    step "Validating script is running on the control node"

    info "Expected control hostname: ${expected_fqdn}"
    info "Current hostname: ${current_hostname}"

    if [[ "$current_hostname" == "$expected_fqdn" ]]; then
        pass "Running on expected control node"
        return 0
    fi

    warn "Current hostname does not match expected control node hostname."
    warn "This script is intended to run from the control node."
    return 1
}


# ==============================================================================
# Target Helpers
# ==============================================================================

get_expected_ip_for_target() {
    local target="$1"

    case "$target" in
        gateway)
            printf '%s\n' "$GATEWAY_IP"
            ;;
        control|ansible1|ansible2|ubuntu)
            get_host_ip_for_role "$target"
            ;;
        *)
            printf '%s\n' "unknown"
            ;;
    esac
}

get_expected_fqdn_for_target() {
    local target="$1"

    case "$target" in
        gateway)
            printf '%s\n' "$GATEWAY_FQDN"
            ;;
        control|ansible1|ansible2|ubuntu)
            get_host_fqdn_for_role "$target"
            ;;
        *)
            printf '%s\n' "unknown"
            ;;
    esac
}


# ==============================================================================
# Log Header
# ==============================================================================

write_ping_log_header() {
    local branch_name
    local current_hostname
    local generated_at

    branch_name="$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || printf '%s\n' 'unknown')"
    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"
    generated_at="$(date '+%Y-%m-%d %H:%M:%S %Z')"

    cat > "$PING_LOG" <<EOF
==============================================================================
NSSA320 Lab 4 - Activity 1 Connectivity Validation
==============================================================================

Generated:      ${generated_at}
Generated By:   $(whoami)
Control Host:   ${current_hostname}
Repository:     ${BASE_DIR}
Git Branch:     ${branch_name}

Network Plan:
  Domain:       ${DOMAIN}
  Network:      ${NETWORK_CIDR}
  Gateway:      ${GATEWAY_IP}
  DNS Servers:  ${DNS_SERVERS}

Ping Targets:
  ${PING_TARGETS}

==============================================================================
EOF
}


# ==============================================================================
# Ping Validation
# ==============================================================================

write_target_log_start() {
    local target="$1"
    local expected_ip="$2"
    local expected_fqdn="$3"

    {
        echo
        echo "------------------------------------------------------------------------------"
        echo "Target:        ${target}"
        echo "Expected IP:   ${expected_ip}"
        echo "Expected FQDN: ${expected_fqdn}"
        echo "Command:       ping -c 4 ${target}"
        echo "Timestamp:     $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "------------------------------------------------------------------------------"
        echo
    } >> "$PING_LOG"
}

run_ping_for_target() {
    local target="$1"
    local expected_ip
    local expected_fqdn
    local resolved_line
    local getent_tmp
    local ping_status=0

    expected_ip="$(get_expected_ip_for_target "$target")"
    expected_fqdn="$(get_expected_fqdn_for_target "$target")"
    getent_tmp="/tmp/lab4_getent_${target}.out"

    step "Pinging ${target}"

    info "Expected IP: ${expected_ip}"
    info "Expected FQDN: ${expected_fqdn}"

    write_target_log_start "$target" "$expected_ip" "$expected_fqdn"

    if getent hosts "$target" > "$getent_tmp" 2>&1; then
        resolved_line="$(head -n 1 "$getent_tmp")"
        pass "Resolved ${target}: ${resolved_line}"

        {
            echo "Name Resolution: PASS"
            echo "Resolved As:     ${resolved_line}"
            echo
        } >> "$PING_LOG"
    else
        fail "Could not resolve ${target}"

        {
            echo "Name Resolution: FAIL"
            echo
            echo "Result: FAIL"
        } >> "$PING_LOG"

        return 1
    fi

    if ping -c 4 "$target" >> "$PING_LOG" 2>&1; then
        pass "Ping succeeded for ${target}"
        ping_status=0

        {
            echo
            echo "Result: PASS"
        } >> "$PING_LOG"
    else
        fail "Ping failed for ${target}"
        ping_status=1

        {
            echo
            echo "Result: FAIL"
        } >> "$PING_LOG"
    fi

    rm -f "$getent_tmp"
    return "$ping_status"
}


# ==============================================================================
# Log Summary
# ==============================================================================

write_ping_log_summary() {
    local passed="$1"
    local failed="$2"

    {
        echo
        echo "=============================================================================="
        echo "Connectivity Validation Summary"
        echo "=============================================================================="
        echo
        echo "Passed Targets: ${passed}"
        echo "Failed Targets: ${failed}"
        echo "Completed:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo
        if [[ "$failed" -eq 0 ]]; then
            echo "Overall Result: PASS"
        else
            echo "Overall Result: FAIL"
        fi
        echo
        echo "=============================================================================="
    } >> "$PING_LOG"
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    local target
    local passed=0
    local failed=0

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    step "Starting Activity 1 connectivity validation"

    prepare_evidence_directories "$EVIDENCE_DIR" "$ARCHIVE_DIR"
    archive_existing_log "$PING_LOG" "$ARCHIVE_DIR" "ping"
    validate_running_on_control_node || warn "Continuing anyway so evidence can still be generated."

    write_ping_log_header

    step "Running ping validation targets"

    for target in $PING_TARGETS; do
        if run_ping_for_target "$target"; then
            passed=$(( passed + 1 ))
        else
            failed=$(( failed + 1 ))
        fi
    done

    write_ping_log_summary "$passed" "$failed"

    step "Connectivity validation summary"

    info "Evidence file: ${PING_LOG}"
    info "Passed targets: ${passed}"
    info "Failed targets: ${failed}"

    show_evidence_location "$PING_LOG" "$ARCHIVE_DIR"

    if [[ "$failed" -eq 0 ]]; then
        pass "Connectivity validation passed"
        pass "Professor-facing evidence created: ${PING_LOG}"
        exit 0
    else
        fail "Connectivity validation completed with failures"
        warn "This may be expected if managed VMs are powered off or not bootstrapped yet."
        info "Professor-facing evidence created: ${PING_LOG}"
        exit 1
    fi
}

main "$@"
