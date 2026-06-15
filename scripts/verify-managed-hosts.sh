#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Activity 3 Managed Host Verification
# File: scripts/verify-managed-hosts.sh
#
# Purpose:
#   Verifies that Activity 3 managed-host setup completed successfully by
#   confirming the inventory exists, key-based SSH works through Ansible,
#   and the ansible service account exists on each managed host.
#
# Scope:
#   Activity 3 only.
#   This script validates managed-host access after setup-managed-hosts.sh.
#
# Safety:
#   Must be run as the normal student user, not with sudo.
#   Does not create users.
#   Does not set passwords.
#   Does not copy SSH keys.
#   Does not configure sudoers files.
#   Does not configure passwordless sudo.
#   Does not create ansible.cfg.
#   Does not perform Activity 4 privilege escalation.
#
# RICE Notes:
#   Reproducibility - runs the same Activity 3 verification sequence each time.
#   Idempotency     - performs verification checks and archives old evidence.
#   Composability   - uses shared config and library functions.
#   Evolvability    - keeps Activity 4 privilege escalation verification separate.
#
# Version History:
#   v3.0 - Initial Activity 3 managed-host verification workflow.
#   v3.1 - Added all-host Figure 3 screenshot capture.

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
FAILURES=0

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME
  $SCRIPT_NAME --help

Description:
  Verifies Lab 4 Activity 3 managed-host setup and captures Figure 3 evidence.

Verification actions:
  1. Confirm the script is running as the normal student user.
  2. Check required local commands.
  3. Confirm the Activity 3 inventory exists.
  4. Capture Figure 3 text evidence.
  5. Validate the ansible service account on all managed hosts.
  6. Capture one screenshot showing all managed-host validation output.

This script does not configure sudoers files, passwordless sudo,
ansible.cfg, or Activity 4 privilege escalation.

EOF
}

record_failure() {
  FAILURES="$((FAILURES + 1))"
}

check_activity3_required_commands() {
  step "Checking Activity 3 required commands"

  local command_name
  for command_name in "${ACTIVITY3_REQUIRED_COMMANDS[@]}"; do
    if command -v "$command_name" >/dev/null 2>&1; then
      pass "Required command found: ${command_name}"
    else
      fail "Required command not found: ${command_name}"
      record_failure
    fi
  done
}

prepare_activity3_evidence_directories() {
  step "Preparing Activity 3 evidence directories"

  mkdir -p "$ACTIVITY3_EVIDENCE_DIR" \
    || die "Failed to create evidence directory: ${ACTIVITY3_EVIDENCE_DIR}"

  mkdir -p "$ACTIVITY3_ARCHIVE_DIR" \
    || die "Failed to create archive directory: ${ACTIVITY3_ARCHIVE_DIR}"

  if [[ ! -w "$ACTIVITY3_EVIDENCE_DIR" ]]; then
    fail "Activity 3 evidence directory is not writable: ${ACTIVITY3_EVIDENCE_DIR}"
    info "This can happen if verification was previously run with sudo."
    info "Recovery command:"
    info "  sudo chown -R student:student ${ACTIVITY3_EVIDENCE_DIR}"
    die "Fix evidence directory ownership before continuing"
  fi

  if [[ ! -w "$ACTIVITY3_ARCHIVE_DIR" ]]; then
    fail "Activity 3 archive directory is not writable: ${ACTIVITY3_ARCHIVE_DIR}"
    info "This can happen if verification was previously run with sudo."
    info "Recovery command:"
    info "  sudo chown -R student:student ${ACTIVITY3_EVIDENCE_DIR}"
    die "Fix evidence archive ownership before continuing"
  fi

  pass "Evidence directory ready: ${ACTIVITY3_EVIDENCE_DIR}"
  pass "Archive directory ready: ${ACTIVITY3_ARCHIVE_DIR}"
}

archive_existing_evidence_file() {
  local evidence_file="$1"
  local archive_dir="$2"
  local file_name
  local file_stem
  local file_extension
  local timestamp
  local archive_path
  local counter

  if [[ -z "$evidence_file" || -z "$archive_dir" ]]; then
    die "Usage: archive_existing_evidence_file <evidence_file> <archive_dir>"
  fi

  if [[ ! -f "$evidence_file" ]]; then
    info "No existing evidence file to archive: ${evidence_file}"
    return 0
  fi

  file_name="$(basename "$evidence_file")"

  if [[ "$file_name" == *.* ]]; then
    file_stem="${file_name%.*}"
    file_extension="${file_name##*.}"
  else
    file_stem="$file_name"
    file_extension="evidence"
  fi

  timestamp="$(date +%Y%m%d-%H%M%S)"
  archive_path="${archive_dir}/${file_stem}-${timestamp}.${file_extension}"
  counter=1

  while [[ -e "$archive_path" ]]; do
    archive_path="${archive_dir}/${file_stem}-${timestamp}-${counter}.${file_extension}"
    counter="$((counter + 1))"
  done

  info "Archiving existing evidence file: ${evidence_file}"
  info "Archive destination: ${archive_path}"

  mv "$evidence_file" "$archive_path" \
    || die "Failed to archive evidence file: ${evidence_file}"

  pass "Archived previous evidence: ${archive_path}"
}

archive_activity3_evidence() {
  step "Archiving existing Activity 3 evidence"

  archive_existing_evidence_file "$ACTIVITY3_VERIFY_OUTPUT" "$ACTIVITY3_ARCHIVE_DIR"
  archive_existing_evidence_file "$ACTIVITY3_FIGURE3_OUTPUT" "$ACTIVITY3_ARCHIVE_DIR"
  archive_existing_evidence_file "$ACTIVITY3_FIGURE3_SCREENSHOT" "$ACTIVITY3_ARCHIVE_DIR"

  pass "Activity 3 evidence archive check complete"
}

capture_activity3_screenshot() {
  local screenshot_file="$1"
  local screenshot_tool_used=""

  if [[ -z "$screenshot_file" ]]; then
    die "Usage: capture_activity3_screenshot <screenshot_file>"
  fi

  step "Capturing Activity 3 screenshot"

  info "Screenshot will be captured after ${ACTIVITY3_SCREENSHOT_DELAY_SECONDS} seconds."
  info "Do not move, cover, resize, or switch away from this terminal."
  sleep "$ACTIVITY3_SCREENSHOT_DELAY_SECONDS"

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
    pass "Screenshot captured with ${screenshot_tool_used}: ${screenshot_file}"
    return 0
  fi

  warn "Automated screenshot capture did not complete."
  warn "Manual fallback: save the screenshot as:"
  warn "  ${screenshot_file}"
  return 0
}

capture_figure3_text_evidence() {
  step "Capturing Figure 3 terminal text evidence"

  {
    echo "Figure 3 - Key-based Authentication Test"
    echo "Activity: ${ACTIVITY3_NAME:-Setting Up Managed Hosts}"
    echo "Version: ${ACTIVITY3_VERSION:-v3.0}"
    echo
    echo "Command: hostname"
    hostname
    echo
    echo "Command: date"
    date
    echo
    echo "Command: whoami"
    whoami
    echo
    echo "Command: cat ${ACTIVITY3_INVENTORY_FILE}"
    cat "$ACTIVITY3_INVENTORY_FILE"
    echo
    echo "Command: ansible -i ${ACTIVITY3_INVENTORY_FILE} ${ACTIVITY3_ALL_GROUP} -m command -a \"id ${ACTIVITY3_SERVICE_USER}\" -u ${ACTIVITY3_REMOTE_USER}"
    ansible -i "$ACTIVITY3_INVENTORY_FILE" "$ACTIVITY3_ALL_GROUP" \
      -m command \
      -a "id ${ACTIVITY3_SERVICE_USER}" \
      -u "$ACTIVITY3_REMOTE_USER"
  } | tee "$ACTIVITY3_FIGURE3_OUTPUT"

  if [[ -s "$ACTIVITY3_FIGURE3_OUTPUT" ]]; then
    pass "Figure 3 text evidence written: ${ACTIVITY3_FIGURE3_OUTPUT}"
  else
    fail "Figure 3 text evidence was not created correctly"
    record_failure
  fi
}

show_activity3_evidence_locations() {
  step "Activity 3 evidence locations"

  info "Verification log: ${ACTIVITY3_VERIFY_OUTPUT}"
  info "Figure 3 text output: ${ACTIVITY3_FIGURE3_OUTPUT}"
  info "Figure 3 screenshot: ${ACTIVITY3_FIGURE3_SCREENSHOT}"
  info "Archive directory: ${ACTIVITY3_ARCHIVE_DIR}"

  if [[ -f "$ACTIVITY3_VERIFY_OUTPUT" ]]; then
    pass "Verification log exists"
  else
    warn "Verification log does not exist yet"
  fi

  if [[ -f "$ACTIVITY3_FIGURE3_OUTPUT" ]]; then
    pass "Figure 3 text output exists"
  else
    warn "Figure 3 text output does not exist yet"
  fi

  if [[ -f "$ACTIVITY3_FIGURE3_SCREENSHOT" ]]; then
    pass "Figure 3 screenshot exists"
  else
    warn "Figure 3 screenshot does not exist yet"
  fi
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    "")
      ;;
    *)
      fail "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac

  require_not_root
  prepare_activity3_evidence_directories
  archive_activity3_evidence

  exec > >(tee "$ACTIVITY3_VERIFY_OUTPUT") 2>&1

  step "Starting Activity 3 managed-host verification"
  info "Activity: ${ACTIVITY3_NAME:-Setting Up Managed Hosts}"
  info "Version: ${ACTIVITY3_VERSION:-v3.0}"
  info "User: $(id -un)"
  info "Repository root: ${REPO_ROOT}"

  check_activity3_required_commands
  require_file "$ACTIVITY3_INVENTORY_FILE"

  capture_figure3_text_evidence
  capture_activity3_screenshot "$ACTIVITY3_FIGURE3_SCREENSHOT"
  show_activity3_evidence_locations

  if [[ "$FAILURES" -gt 0 ]]; then
    fail "Activity 3 verification completed with ${FAILURES} issue(s)."
    return 1
  fi

  pass "Activity 3 verification completed successfully."
  return 0
}

main "$@"
