#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Activity 4 Privilege Escalation Setup
# File: scripts/setup-privilege-escalation.sh
#
# Purpose:
# Prepares Activity 4 privileged escalation by configuring password-less sudo
# on the control node, validating the Activity 3 inventory, deploying sudoers
# files to managed hosts, and creating the Activity 4 ansible.cfg file.
#
# Scope:
# Activity 4 only.
# This script assumes Activity 3 already created inventory and SSH access.
#
# Safety:
# Supports --dry-run and --apply modes.
# Must be run as the normal student user, not with sudo.
# Does not create managed users.
# Does not set managed user passwords.
# Does not generate or copy SSH keys.
# Does not capture screenshots.
#
# RICE Notes:
# Reproducibility - runs the same Activity 4 setup sequence each time.
# Idempotency - sudoers files and ansible.cfg are safely rewritten with
#               validated expected content.
# Composability - uses shared config, evidence, and privilege helper libraries.
# Evolvability - keeps verification and screenshot capture in a separate script.
#
# Version History:
# v4.0 - Initial Activity 4 privilege escalation setup workflow.

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
Usage: ${SCRIPT_NAME} --dry-run | --apply | --help

Options:
  --dry-run   Show the Activity 4 setup plan without making changes.
  --apply     Apply Activity 4 privilege escalation setup.
  --help      Show this help message.

Examples:
  ./scripts/${SCRIPT_NAME} --dry-run
  ./scripts/${SCRIPT_NAME} --apply
USAGE
}

dry_run() {
    step "Activity 4 dry run starting"

    require_not_root
    activity4_show_context
    activity4_check_required_commands

    step "Dry-run setup plan"

    if [[ -f "$ACTIVITY4_CONTROL_SUDOERS_FILE" ]]; then
        info "Control sudoers file exists: ${ACTIVITY4_CONTROL_SUDOERS_FILE}"
        info "Would validate and rewrite it only during --apply."
    else
        warn "Would create control sudoers file: ${ACTIVITY4_CONTROL_SUDOERS_FILE}"
    fi

    info "Would verify control-node password-less sudo with: sudo -n ls -ld /root"

    if [[ -f "$ACTIVITY4_INVENTORY_FILE" ]]; then
        pass "Inventory file exists: ${ACTIVITY4_INVENTORY_FILE}"
        info "Would pre-check inventory data for ubuntu, ansible1, ansible2, ubuntu_hosts, and rocky_hosts."
    else
        warn "Inventory file is missing: ${ACTIVITY4_INVENTORY_FILE}"
    fi

    info "Would create temporary ansible sudoers source file: ${ACTIVITY4_TEMP_SUDOERS_FILE:-/tmp/sudoers}"

    info "Would deploy ansible sudoers file to Rocky hosts: ${ACTIVITY4_ROCKY_GROUP}"
    info "Would deploy ansible sudoers file to Ubuntu hosts: ${ACTIVITY4_UBUNTU_GROUP}"
    info "Would deploy student sudoers file to all managed hosts: ${ACTIVITY4_ALL_GROUP}"
    info "Would validate sudoers files on managed hosts with visudo."

    if [[ -f "$ACTIVITY4_ANSIBLE_CFG" ]]; then
        info "Ansible config exists: ${ACTIVITY4_ANSIBLE_CFG}"
        info "Would verify or rewrite expected Activity 4 ansible.cfg values during --apply."
    else
        warn "Would create ansible config: ${ACTIVITY4_ANSIBLE_CFG}"
    fi

    step "Activity 4 dry run complete"
    pass "No changes were made."
}

apply_actions() {
    step "Activity 4 apply starting"

    require_not_root
    activity4_show_context
    activity4_check_required_commands

    activity4_install_control_sudoers
    activity4_verify_control_sudo

    activity4_precheck_inventory

    activity4_create_temp_ansible_sudoers_file
    activity4_deploy_ansible_sudoers_to_group "$ACTIVITY4_ROCKY_GROUP"
    activity4_deploy_ansible_sudoers_to_group "$ACTIVITY4_UBUNTU_GROUP"
    activity4_deploy_student_sudoers_to_managed_hosts
    activity4_validate_managed_sudoers

    activity4_write_ansible_cfg
    activity4_verify_ansible_cfg

    step "Activity 4 apply complete"
    pass "Privilege escalation setup completed."
    info "Setup evidence saved to: ${ACTIVITY4_SETUP_OUTPUT}"
}

apply_setup() {
    prepare_evidence_directories "$ACTIVITY4_EVIDENCE_DIR" "$ACTIVITY4_ARCHIVE_DIR"
    archive_existing_log "$ACTIVITY4_SETUP_OUTPUT" "$ACTIVITY4_ARCHIVE_DIR" "privilege-escalation-setup"

    exec > >(tee "$ACTIVITY4_SETUP_OUTPUT") 2>&1

    apply_actions
}

main() {
    case "${1:-}" in
        --dry-run)
            dry_run
            ;;
        --apply)
            apply_setup
            ;;
        -h|--help)
            usage
            ;;
        "")
            fail "Missing required mode."
            usage
            exit 2
            ;;
        *)
            fail "Unknown argument: $1"
            usage
            exit 2
            ;;
    esac
}

main "$@"
