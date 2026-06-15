#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Activity 3 Managed Host Setup
# File: scripts/setup-managed-hosts.sh
#
# Purpose:
#   Prepares the Lab 4 managed hosts for Ansible access by creating the
#   required lab inventory, verifying basic SSH access as the student user,
#   creating the ansible service account, setting the lab-required ansible
#   account password, generating an SSH key only if missing, and copying the
#   public key to each managed host.
#
# Scope:
#   Activity 3 only.
#   This script prepares ubuntu, ansible1, and ansible2 as managed hosts.
#
# Safety:
#   Supports --dry-run and --apply modes.
#   Must be run as the normal student user, not with sudo.
#   Does not store the student password.
#   Does not configure sudoers files.
#   Does not configure passwordless sudo.
#   Does not create ansible.cfg.
#   Does not perform Activity 4 privilege escalation.
#
# RICE Notes:
#   Reproducibility - runs the same Activity 3 setup sequence each time.
#   Idempotency     - reuses existing SSH keys and only rewrites inventory
#                     when the expected content is missing or different.
#   Composability   - uses shared config and library functions.
#   Evolvability    - keeps Activity 4 privilege escalation separate.
#
# Version History:
#   v3.0 - Initial Activity 3 managed-host setup workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Source shared configuration and libraries
# ---------------------------------------------------------------------------

source config/lab4.conf
source config/activity3.conf
source lib/common.sh
source lib/evidence.sh
source lib/ssh.sh

SCRIPT_NAME="$(basename "$0")"

# Lab-required password for the ansible service account.
# This is not the student's password.
# This value comes from the lab instructions and is only used for the lab.
ACTIVITY3_LAB_SERVICE_PASSWORD="password"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --apply
  $SCRIPT_NAME --help

Description:
  Prepares Lab 4 Activity 3 managed hosts for Ansible access.

Modes:
  --dry-run   Show what would be checked or changed, but do not change hosts.
  --apply     Apply Activity 3 managed-host setup steps.

Activity 3 actions:
  1. Confirm the script is running as the normal student user.
  2. Check required local commands.
  3. Prepare Activity 3 evidence directories.
  4. Create ${ACTIVITY3_LAB_DIR}.
  5. Create or update ${ACTIVITY3_INVENTORY_FILE}.
  6. Verify basic SSH access as ${ACTIVITY3_REMOTE_USER}.
  7. Create the ${ACTIVITY3_SERVICE_USER} service account on Ubuntu.
  8. Create the ${ACTIVITY3_SERVICE_USER} service account on Rocky hosts.
  9. Set the lab-required ${ACTIVITY3_SERVICE_USER} account password.
  10. Generate a local SSH key only if missing.
  11. Copy the SSH public key to all managed hosts.

This script does not configure sudoers files, passwordless sudo,
ansible.cfg, or Activity 4 privilege escalation.

EOF
}

show_activity_context() {
  step "Activity 3 context"

  info "Repository root: ${REPO_ROOT}"
  info "Activity version: ${ACTIVITY3_VERSION}"
  info "Activity name: ${ACTIVITY3_NAME}"
  info "Lab directory: ${ACTIVITY3_LAB_DIR}"
  info "Inventory file: ${ACTIVITY3_INVENTORY_FILE}"
  info "Remote SSH user: ${ACTIVITY3_REMOTE_USER}"
  info "Service account user: ${ACTIVITY3_SERVICE_USER}"
  info "Evidence directory: ${ACTIVITY3_EVIDENCE_DIR}"
  info "Archive directory: ${ACTIVITY3_ARCHIVE_DIR}"

  local host
  info "Managed hosts:"
  for host in "${ACTIVITY3_MANAGED_HOSTS[@]}"; do
    info "  - ${host}"
  done
}

check_activity3_required_commands() {
  step "Checking Activity 3 required commands"

  local command_name
  for command_name in "${ACTIVITY3_REQUIRED_COMMANDS[@]}"; do
    require_command "$command_name"
  done
}

create_lab_directory() {
  step "Preparing Activity 3 lab directory"

  if [[ -d "$ACTIVITY3_LAB_DIR" ]]; then
    pass "Lab directory already exists: ${ACTIVITY3_LAB_DIR}"
  else
    mkdir -p "$ACTIVITY3_LAB_DIR" || die "Failed to create lab directory: ${ACTIVITY3_LAB_DIR}"
    pass "Lab directory created: ${ACTIVITY3_LAB_DIR}"
  fi
}

create_or_update_inventory() {
  step "Creating or updating Activity 3 inventory"

  local current_content

  mkdir -p "$(dirname "$ACTIVITY3_INVENTORY_FILE")" \
    || die "Failed to create inventory directory"

  if [[ -f "$ACTIVITY3_INVENTORY_FILE" ]]; then
    current_content="$(cat "$ACTIVITY3_INVENTORY_FILE")"

    if [[ "$current_content" == "${ACTIVITY3_INVENTORY_CONTENT%$'\n'}" ]]; then
      pass "Inventory already matches expected content: ${ACTIVITY3_INVENTORY_FILE}"
      return 0
    fi

    warn "Inventory exists but does not match expected Activity 3 content."
    info "Updating inventory file: ${ACTIVITY3_INVENTORY_FILE}"
  else
    info "Inventory file does not exist. Creating: ${ACTIVITY3_INVENTORY_FILE}"
  fi

  printf '%s' "$ACTIVITY3_INVENTORY_CONTENT" > "$ACTIVITY3_INVENTORY_FILE" \
    || die "Failed to write inventory file: ${ACTIVITY3_INVENTORY_FILE}"

  pass "Inventory file ready: ${ACTIVITY3_INVENTORY_FILE}"

  info "Inventory content:"
  cat "$ACTIVITY3_INVENTORY_FILE"
}

dry_run() {
  step "Activity 3 dry run starting"

  require_not_root
  show_activity_context
  check_activity3_required_commands

  step "Dry-run setup plan"

  if [[ -d "$ACTIVITY3_LAB_DIR" ]]; then
    pass "Lab directory already exists: ${ACTIVITY3_LAB_DIR}"
  else
    warn "Would create lab directory: ${ACTIVITY3_LAB_DIR}"
  fi

  if [[ -f "$ACTIVITY3_INVENTORY_FILE" ]]; then
    info "Inventory file exists: ${ACTIVITY3_INVENTORY_FILE}"
    info "Would verify inventory content and update only if different."
  else
    warn "Would create inventory file: ${ACTIVITY3_INVENTORY_FILE}"
  fi

  info "Would verify basic SSH access to managed hosts as ${ACTIVITY3_REMOTE_USER}:"
  local host
  for host in "${ACTIVITY3_MANAGED_HOSTS[@]}"; do
    info "Would run: ssh ${ACTIVITY3_REMOTE_USER}@${host} 'hostname; whoami; date'"
  done

  info "Would create ${ACTIVITY3_SERVICE_USER} account on Ubuntu group:"
  info "ansible -i ${ACTIVITY3_INVENTORY_FILE} ${ACTIVITY3_UBUNTU_GROUP} -m user -a \"name=${ACTIVITY3_SERVICE_USER} create_home=yes\" -u ${ACTIVITY3_REMOTE_USER} -b -k -K"

  info "Would create ${ACTIVITY3_SERVICE_USER} account on Rocky group:"
  info "ansible -i ${ACTIVITY3_INVENTORY_FILE} ${ACTIVITY3_ROCKY_GROUP} -m user -a \"name=${ACTIVITY3_SERVICE_USER} create_home=yes\" -u ${ACTIVITY3_REMOTE_USER} -b -k -K"

  info "Would set lab-required ${ACTIVITY3_SERVICE_USER} account password on Ubuntu group."
  info "Would set lab-required ${ACTIVITY3_SERVICE_USER} account password on Rocky group."

  if [[ -f "$ACTIVITY3_SSH_KEY_PATH" && -f "$ACTIVITY3_SSH_PUBLIC_KEY_PATH" ]]; then
    pass "Existing SSH key pair found. Would reuse: ${ACTIVITY3_SSH_KEY_PATH}"
  else
    warn "Would generate SSH key pair: ${ACTIVITY3_SSH_KEY_PATH}"
  fi

  info "Would copy SSH public key to managed hosts:"
  for host in "${ACTIVITY3_MANAGED_HOSTS[@]}"; do
    info "Would run: ssh-copy-id ${ACTIVITY3_REMOTE_USER}@${host}"
  done

  step "Activity 3 dry run complete"
  pass "No changes were made."
}

run_ansible_user_creation() {
  step "Creating ansible service account on managed hosts"

  info "Creating ${ACTIVITY3_SERVICE_USER} on Ubuntu hosts"
  ansible -i "$ACTIVITY3_INVENTORY_FILE" "$ACTIVITY3_UBUNTU_GROUP" \
    -m user \
    -a "name=${ACTIVITY3_SERVICE_USER} create_home=yes" \
    -u "$ACTIVITY3_REMOTE_USER" \
    -b -k -K \
    || die "Failed to create ${ACTIVITY3_SERVICE_USER} on Ubuntu hosts"

  pass "Ubuntu service account task completed"

  info "Creating ${ACTIVITY3_SERVICE_USER} on Rocky hosts"
  ansible -i "$ACTIVITY3_INVENTORY_FILE" "$ACTIVITY3_ROCKY_GROUP" \
    -m user \
    -a "name=${ACTIVITY3_SERVICE_USER} create_home=yes" \
    -u "$ACTIVITY3_REMOTE_USER" \
    -b -k -K \
    || die "Failed to create ${ACTIVITY3_SERVICE_USER} on Rocky hosts"

  pass "Rocky service account task completed"
}

run_ansible_password_setup() {
  step "Setting lab-required ansible service account password"

  info "Setting ${ACTIVITY3_SERVICE_USER} password on Ubuntu hosts"
  ansible -i "$ACTIVITY3_INVENTORY_FILE" "$ACTIVITY3_UBUNTU_GROUP" \
    -m shell \
    -a "echo '${ACTIVITY3_SERVICE_USER}:${ACTIVITY3_LAB_SERVICE_PASSWORD}' | chpasswd" \
    -u "$ACTIVITY3_REMOTE_USER" \
    -b -k -K \
    || die "Failed to set ${ACTIVITY3_SERVICE_USER} password on Ubuntu hosts"

  pass "Ubuntu service account password task completed"

  info "Setting ${ACTIVITY3_SERVICE_USER} password on Rocky hosts"
  ansible -i "$ACTIVITY3_INVENTORY_FILE" "$ACTIVITY3_ROCKY_GROUP" \
    -m shell \
    -a "echo '${ACTIVITY3_SERVICE_USER}:${ACTIVITY3_LAB_SERVICE_PASSWORD}' | chpasswd" \
    -u "$ACTIVITY3_REMOTE_USER" \
    -b -k -K \
    || die "Failed to set ${ACTIVITY3_SERVICE_USER} password on Rocky hosts"

  pass "Rocky service account password task completed"
}

apply_actions() {
  step "Activity 3 apply starting"

  require_not_root
  show_activity_context
  check_activity3_required_commands

  create_lab_directory
  create_or_update_inventory

  activity3_verify_basic_ssh_access \
    "$ACTIVITY3_REMOTE_USER" \
    "${ACTIVITY3_MANAGED_HOSTS[@]}"

  run_ansible_user_creation
  run_ansible_password_setup

  activity3_ensure_local_ssh_key \
    "$ACTIVITY3_SSH_KEY_PATH" \
    "$ACTIVITY3_SSH_PUBLIC_KEY_PATH"

  activity3_copy_ssh_key_to_managed_hosts \
    "$ACTIVITY3_REMOTE_USER" \
    "${ACTIVITY3_MANAGED_HOSTS[@]}"

  step "Activity 3 apply complete"
  pass "Managed host setup completed."
  info "Setup evidence saved to: ${ACTIVITY3_SETUP_OUTPUT}"
}

apply_setup() {
  prepare_evidence_directories "$ACTIVITY3_EVIDENCE_DIR" "$ACTIVITY3_ARCHIVE_DIR"
  archive_existing_log "$ACTIVITY3_SETUP_OUTPUT" "$ACTIVITY3_ARCHIVE_DIR" "managed-hosts-setup"

  exec > >(tee "$ACTIVITY3_SETUP_OUTPUT") 2>&1

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
