#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Activity 4 Privilege Escalation Verification
# File: scripts/verify-privilege-escalation.sh
#
# Purpose:
# Verifies Activity 4 privileged escalation by checking control-node sudo,
# Activity 3 inventory reuse, managed-host sudoers validation, ansible.cfg,
# and privileged Ansible execution without repeated interactive flags.
#
# Scope:
# Activity 4 only.
# This script verifies the setup and captures professor-facing evidence.
#
# Safety:
# Must be run as the normal student user, not with sudo.
# Does not create users.
# Does not set passwords.
# Does not generate or copy SSH keys.
# Does not deploy sudoers files.
# Does not modify ansible.cfg.
#
# RICE Notes:
# Reproducibility - runs the same verification sequence each time.
# Idempotency - archives old evidence before generating new evidence.
# Composability - uses shared config, evidence, and privilege helper libraries.
# Evolvability - keeps screenshot capture isolated in the verification workflow.
#
# Version History:
# v4.0 - Initial Activity 4 privilege escalation verification workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Source shared configuration and libraries
# ---------------------------------------------------------------------------
source config/lab4.conf
source config/activity4.conf
source lib/common.sh
source lib/evidence.sh
source lib/privilege.sh

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<USAGE
Usage: ${SCRIPT_NAME} [--help]

Verifies Activity 4 privilege escalation and captures evidence.

Examples:
  ./scripts/${SCRIPT_NAME}
  ./scripts/${SCRIPT_NAME} --help
USAGE
}

archive_existing_evidence_file() {
    local evidence_file="$1"
    local archive_dir="$2"
    local evidence_prefix="$3"
    local timestamp
    local basename_only
    local extension
    local archived_file

    step "Checking for existing evidence file"

    if [[ -z "$evidence_file" || -z "$archive_dir" || -z "$evidence_prefix" ]]; then
        die "Usage: archive_existing_evidence_file <evidence_file> <archive_dir> <evidence_prefix>"
    fi

    if [[ ! -f "$evidence_file" ]]; then
        pass "No existing evidence file found: ${evidence_file}"
        return 0
    fi

    mkdir -p "$archive_dir" || die "Failed to create archive directory: ${archive_dir}"

    timestamp="$(date +%Y%m%d-%H%M%S)"
    basename_only="$(basename "$evidence_file")"

    if [[ "$basename_only" == *.* ]]; then
        extension=".${basename_only##*.}"
    else
        extension=""
    fi

    archived_file="${archive_dir}/${evidence_prefix}-${timestamp}${extension}"

    info "Existing evidence file found: ${evidence_file}"
    info "Archiving old evidence to: ${archived_file}"

    mv "$evidence_file" "$archived_file" || die "Failed to archive existing evidence file"

    pass "Previous evidence file archived successfully."
}

archive_activity4_evidence() {
    prepare_evidence_directories "$ACTIVITY4_EVIDENCE_DIR" "$ACTIVITY4_ARCHIVE_DIR"

    archive_existing_log \
        "$ACTIVITY4_VERIFY_OUTPUT" \
        "$ACTIVITY4_ARCHIVE_DIR" \
        "privilege-escalation-verification"

    archive_existing_evidence_file \
        "$ACTIVITY4_FIGURE4_OUTPUT" \
        "$ACTIVITY4_ARCHIVE_DIR" \
        "figure4-privilege-escalation-test"

    archive_existing_evidence_file \
        "$ACTIVITY4_FIGURE4_SCREENSHOT" \
        "$ACTIVITY4_ARCHIVE_DIR" \
        "figure4-privilege-escalation-test"
}

capture_figure4_text_evidence() {
    step "Capturing Figure 4 privilege escalation text evidence"

    {
        echo "NSSA320 Lab 4 - Activity 4 Figure 4 Evidence"
        echo "Generated: $(date)"
        echo "Control node: $(hostname)"
        echo
        echo "Working directory:"
        echo "$ACTIVITY4_LAB_DIR"
        echo
        echo "Ansible configuration:"
        cat "$ACTIVITY4_ANSIBLE_CFG"
        echo
        echo "Inventory:"
        cat "$ACTIVITY4_INVENTORY_FILE"
        echo
        echo "Privileged Ansible command without -b, -k, or -K:"
        echo "Command: ansible all -m command -a \"ls -ld /root\""
        echo
        (
            cd "$ACTIVITY4_LAB_DIR"
            ansible all -m command -a "ls -ld /root"
        )
    } | tee "$ACTIVITY4_FIGURE4_OUTPUT"

    pass "Figure 4 text evidence saved to: ${ACTIVITY4_FIGURE4_OUTPUT}"
}

capture_figure4_screenshot() {
    step "Capturing Figure 4 screenshot evidence"

    local screenshot_file="$ACTIVITY4_FIGURE4_SCREENSHOT"
    local screenshot_tool_used=""

    info "Screenshot target: ${screenshot_file}"
    info "Waiting ${ACTIVITY4_SCREENSHOT_DELAY_SECONDS} seconds before screenshot capture."
    sleep "$ACTIVITY4_SCREENSHOT_DELAY_SECONDS"

    if command -v gnome-screenshot >/dev/null 2>&1; then
        if gnome-screenshot -f "$screenshot_file" >/dev/null 2>&1; then
            screenshot_tool_used="gnome-screenshot"
        else
            warn "gnome-screenshot failed to save screenshot."
        fi
    fi

    if [[ -z "$screenshot_tool_used" ]] && command -v scrot >/dev/null 2>&1; then
        if scrot "$screenshot_file" >/dev/null 2>&1; then
            screenshot_tool_used="scrot"
        else
            warn "scrot failed to save screenshot."
        fi
    fi

    if [[ -z "$screenshot_tool_used" ]] && command -v import >/dev/null 2>&1; then
        if import -window root "$screenshot_file" >/dev/null 2>&1; then
            screenshot_tool_used="import"
        else
            warn "ImageMagick import failed to save screenshot."
        fi
    fi

    if [[ -n "$screenshot_tool_used" && -f "$screenshot_file" ]]; then
        pass "Screenshot saved with ${screenshot_tool_used}: ${screenshot_file}"
    else
        warn "Automatic screenshot capture did not complete."
        warn "Manually save the Figure 4 screenshot to: ${screenshot_file}"
    fi
}

verify_activity4() {
    step "Activity 4 verification starting"

    require_not_root
    activity4_show_context
    activity4_check_required_commands

    activity4_verify_control_sudo
    activity4_precheck_inventory
    activity4_verify_ansible_cfg
    activity4_validate_managed_sudoers
    activity4_verify_privileged_ansible_command

    capture_figure4_text_evidence
    capture_figure4_screenshot

    step "Activity 4 verification complete"
    pass "Privilege escalation verification completed."
    info "Verification evidence saved to: ${ACTIVITY4_VERIFY_OUTPUT}"
    info "Figure 4 text evidence saved to: ${ACTIVITY4_FIGURE4_OUTPUT}"
    info "Figure 4 screenshot target: ${ACTIVITY4_FIGURE4_SCREENSHOT}"

    show_evidence_location "$ACTIVITY4_VERIFY_OUTPUT" "$ACTIVITY4_ARCHIVE_DIR"
}

main() {
    case "${1:-}" in
        -h|--help)
            usage
            ;;
        "")
            archive_activity4_evidence
            exec > >(tee "$ACTIVITY4_VERIFY_OUTPUT") 2>&1
            verify_activity4
            ;;
        *)
            fail "Unknown argument: $1"
            usage
            exit 2
            ;;
    esac
}

main "$@"
