#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Activity 2 Control Node Verification
# File: scripts/verify-control-node.sh
#
# Purpose:
#   Verifies the RHEL 8 control node after Activity 2 setup and captures
#   professor-facing Figure 2 evidence for Ansible installation.
#
# Scope:
#   Activity 2 only.
#   This script verifies the control node only.
#
# Safety:
#   Read-only workflow.
#   Does not install packages.
#   Does not update packages.
#   Does not register, unregister, refresh, or overwrite Red Hat licensing.
#   Does not configure managed hosts, SSH keys, Ansible users, or sudoers files.
#
# RICE Notes:
#   Reproducibility - runs the same verification sequence each time.
#   Idempotency     - read-only validation with no system changes.
#   Composability   - uses shared config and library functions.
#   Evolvability    - screenshot tooling can be expanded without changing setup.
#
# Version History:
#   v2.0 - Initial Activity 2 verification and evidence workflow.
#   v2.1 - Added automated Figure 2 screenshot capture with text evidence backup.
#   v2.1.1 - Added graphical display preflight check for safer screenshot capture.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Source shared configuration and libraries
# ---------------------------------------------------------------------------

source config/lab4.conf
source config/activity2.conf
source lib/common.sh
source lib/redhat.sh
source lib/packages.sh

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME
  $SCRIPT_NAME --help

Description:
  Runs read-only Activity 2 verification and captures Figure 2 screenshot
  evidence for the Ansible control-node installation.

Professor-facing Figure 2 command:
  hostname; date; ansible --version

Evidence outputs:
  Text log:
    ${ACTIVITY2_FIGURE2_OUTPUT}

  Screenshot:
    ${ACTIVITY2_FIGURE2_SCREENSHOT}

Notes:
  The screenshot is the primary professor-facing deliverable.
  The text log is supporting evidence for troubleshooting and documentation.

  Automatic screenshot capture requires a graphical desktop session.
  If this script is run over SSH or from a non-GUI terminal, it will still
  print the Figure 2 evidence block and save the text log, but screenshot
  capture may need to be done manually.

EOF
}

print_figure2_block() {
  clear || true

  printf '\n'
  printf '============================================================\n'
  printf ' Figure 2 - Ansible Install Verification\n'
  printf '============================================================\n'
  printf '\n'
  printf '$ hostname; date; ansible --version\n'
  printf '\n'

  hostname
  date
  ansible --version

  printf '\n'
  printf '============================================================\n'
  printf ' Screenshot requirement satisfied:\n'
  printf '   hostname; date; ansible --version\n'
  printf '============================================================\n'
  printf '\n'
}

graphical_display_available() {
  if [[ -z "${DISPLAY:-}" ]]; then
    warn "DISPLAY is not set. Graphical screenshot capture is unavailable."
    return 1
  fi

  if [[ "$DISPLAY" =~ ^:([0-9]+) ]]; then
    local display_number="${BASH_REMATCH[1]}"

    if [[ ! -S "/tmp/.X11-unix/X${display_number}" ]]; then
      warn "DISPLAY is set to ${DISPLAY}, but the X11 socket is not available."
      return 1
    fi
  fi

  pass "Graphical display appears available: ${DISPLAY}"
}

capture_screenshot_with_available_tool() {
  step "Capturing Figure 2 screenshot"

  mkdir -p "$ACTIVITY2_EVIDENCE_DIR"

  if ! graphical_display_available; then
    warn "Automatic screenshot capture requires a graphical desktop session."
    warn "If connected over SSH or a non-GUI terminal, the VM cannot capture the visible host terminal."
    warn "Manual fallback: screenshot the Figure 2 terminal block above."
    return 1
  fi

  if command -v gnome-screenshot >/dev/null 2>&1; then
    info "Screenshot tool found: gnome-screenshot"
    info "Screenshot will be captured in ${ACTIVITY2_SCREENSHOT_DELAY_SECONDS} seconds."
    info "Keep the Figure 2 terminal block visible."

    sleep "$ACTIVITY2_SCREENSHOT_DELAY_SECONDS"

    if gnome-screenshot -f "$ACTIVITY2_FIGURE2_SCREENSHOT"; then
      if [[ -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
        pass "Screenshot saved to: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
        return 0
      fi
    fi

    warn "gnome-screenshot failed or screenshot file was not found."
  fi

  if command -v scrot >/dev/null 2>&1; then
    info "Screenshot tool found: scrot"
    info "Screenshot will be captured in ${ACTIVITY2_SCREENSHOT_DELAY_SECONDS} seconds."
    info "Keep the Figure 2 terminal block visible."

    sleep "$ACTIVITY2_SCREENSHOT_DELAY_SECONDS"

    if scrot "$ACTIVITY2_FIGURE2_SCREENSHOT"; then
      if [[ -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
        pass "Screenshot saved to: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
        return 0
      fi
    fi

    warn "scrot failed or screenshot file was not found."
  fi

  if command -v import >/dev/null 2>&1; then
    info "Screenshot tool found: import"
    info "Screenshot will be captured in ${ACTIVITY2_SCREENSHOT_DELAY_SECONDS} seconds."
    info "Click the terminal window when the cursor changes."

    sleep "$ACTIVITY2_SCREENSHOT_DELAY_SECONDS"

    if import "$ACTIVITY2_FIGURE2_SCREENSHOT"; then
      if [[ -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
        pass "Screenshot saved to: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
        return 0
      fi
    fi

    warn "import failed or screenshot file was not found."
  fi

  warn "No supported screenshot tool successfully captured Figure 2."
  warn "Manual fallback: screenshot the Figure 2 terminal block above."
  return 1
}

write_text_evidence() {
  step "Writing supporting text evidence"

  mkdir -p "$ACTIVITY2_EVIDENCE_DIR"

  {
    printf 'Figure 2 - Ansible Install Verification\n'
    printf 'Generated by: %s\n' "$SCRIPT_NAME"
    printf 'Activity: %s\n' "${ACTIVITY2_NAME}"
    printf 'Activity version: %s\n' "${ACTIVITY2_VERSION}"
    printf '\n'
    printf '$ hostname; date; ansible --version\n'
    hostname
    date
    ansible --version
    printf '\n'
    printf 'Supporting checks:\n'
    python3 --version
    rpm -q epel-release
    rpm -q ansible
  } > "$ACTIVITY2_FIGURE2_OUTPUT"

  pass "Text evidence saved to: ${ACTIVITY2_FIGURE2_OUTPUT}"
}

run_preflight_checks() {
  step "Running Activity 2 verification preflight checks"

  check_rhel_release
  check_subscription_manager_available
  check_subscription_identity
  check_subscription_status
  check_codeready_builder_enabled
  check_deprecated_ansible_repo_not_enabled

  step "Checking installed Activity 2 packages"

  check_package_installed epel-release
  check_package_installed ansible

  step "Checking required commands"

  check_command_available hostname
  check_command_available date
  check_command_available ansible
  check_command_available python3
}

run_verification() {
  run_preflight_checks

  write_text_evidence

  step "Displaying professor-facing Figure 2 evidence"
  info "The next screen is designed for screenshot capture."
  info "Required visible command: hostname; date; ansible --version"
  info "Screenshot title: Figure 2 – Ansible Install Verification"
  sleep 2

  print_figure2_block

  capture_screenshot_with_available_tool || true

  printf '\n'
  pass "Activity 2 Figure 2 verification workflow complete."
  info "Screenshot path: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
  info "Text evidence path: ${ACTIVITY2_FIGURE2_OUTPUT}"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      ;;
    "")
      run_verification
      ;;
    *)
      fail "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
}

main "$@"
# ---------------------------------------------------------------------------
# Source shared configuration and libraries
# ---------------------------------------------------------------------------

source config/lab4.conf
source config/activity2.conf
source lib/common.sh
source lib/redhat.sh
source lib/packages.sh

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME
  $SCRIPT_NAME --help

Description:
  Runs read-only Activity 2 verification and captures Figure 2 screenshot
  evidence for the Ansible control-node installation.

Professor-facing Figure 2 command:
  hostname; date; ansible --version

Evidence outputs:
  Text log:
    ${ACTIVITY2_FIGURE2_OUTPUT}

  Screenshot:
    ${ACTIVITY2_FIGURE2_SCREENSHOT}

Notes:
  The screenshot is the primary professor-facing deliverable.
  The text log is supporting evidence for troubleshooting and documentation.

EOF
}

print_figure2_block() {
  clear || true

  printf '\n'
  printf '============================================================\n'
  printf ' Figure 2 - Ansible Install Verification\n'
  printf '============================================================\n'
  printf '\n'
  printf '$ hostname; date; ansible --version\n'
  printf '\n'

  hostname
  date
  ansible --version

  printf '\n'
  printf '============================================================\n'
  printf ' Screenshot requirement satisfied:\n'
  printf '   hostname; date; ansible --version\n'
  printf '============================================================\n'
  printf '\n'
}

capture_screenshot_with_available_tool() {
  step "Capturing Figure 2 screenshot"

  mkdir -p "$ACTIVITY2_EVIDENCE_DIR"

  if command -v gnome-screenshot >/dev/null 2>&1; then
    info "Screenshot tool found: gnome-screenshot"
    info "Screenshot will be captured in ${ACTIVITY2_SCREENSHOT_DELAY_SECONDS} seconds."
    info "Keep the Figure 2 terminal block visible."

    sleep "$ACTIVITY2_SCREENSHOT_DELAY_SECONDS"

    gnome-screenshot -f "$ACTIVITY2_FIGURE2_SCREENSHOT"

    if [[ -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
      pass "Screenshot saved to: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
      return 0
    fi

    warn "gnome-screenshot ran, but screenshot file was not found."
  fi

  if command -v import >/dev/null 2>&1; then
    info "Screenshot tool found: import"
    info "Screenshot will be captured in ${ACTIVITY2_SCREENSHOT_DELAY_SECONDS} seconds."
    info "Click the terminal window when the cursor changes."

    sleep "$ACTIVITY2_SCREENSHOT_DELAY_SECONDS"

    import "$ACTIVITY2_FIGURE2_SCREENSHOT"

    if [[ -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
      pass "Screenshot saved to: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
      return 0
    fi

    warn "import ran, but screenshot file was not found."
  fi

  if command -v scrot >/dev/null 2>&1; then
    info "Screenshot tool found: scrot"
    info "Screenshot will be captured in ${ACTIVITY2_SCREENSHOT_DELAY_SECONDS} seconds."
    info "Keep the Figure 2 terminal block visible."

    sleep "$ACTIVITY2_SCREENSHOT_DELAY_SECONDS"

    scrot "$ACTIVITY2_FIGURE2_SCREENSHOT"

    if [[ -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
      pass "Screenshot saved to: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
      return 0
    fi

    warn "scrot ran, but screenshot file was not found."
  fi

  warn "No supported screenshot tool was found."
  warn "Install or use one of: gnome-screenshot, import, or scrot."
  warn "Manual fallback: screenshot the Figure 2 terminal block above."
  return 1
}

write_text_evidence() {
  step "Writing supporting text evidence"

  mkdir -p "$ACTIVITY2_EVIDENCE_DIR"

  {
    printf 'Figure 2 - Ansible Install Verification\n'
    printf 'Generated by: %s\n' "$SCRIPT_NAME"
    printf 'Activity: %s\n' "${ACTIVITY2_NAME}"
    printf 'Activity version: %s\n' "${ACTIVITY2_VERSION}"
    printf '\n'
    printf '$ hostname; date; ansible --version\n'
    hostname
    date
    ansible --version
    printf '\n'
    printf 'Supporting checks:\n'
    python3 --version
    rpm -q epel-release
    rpm -q ansible
  } > "$ACTIVITY2_FIGURE2_OUTPUT"

  pass "Text evidence saved to: ${ACTIVITY2_FIGURE2_OUTPUT}"
}

run_preflight_checks() {
  step "Running Activity 2 verification preflight checks"

  check_rhel_release
  check_subscription_manager_available
  check_subscription_identity
  check_subscription_status
  check_codeready_builder_enabled
  check_deprecated_ansible_repo_not_enabled

  step "Checking installed Activity 2 packages"

  check_package_installed epel-release
  check_package_installed ansible

  step "Checking required commands"

  check_command_available hostname
  check_command_available date
  check_command_available ansible
  check_command_available python3
}

run_verification() {
  run_preflight_checks

  write_text_evidence

  step "Displaying professor-facing Figure 2 evidence"
  info "The next screen is designed for screenshot capture."
  info "Required visible command: hostname; date; ansible --version"
  info "Screenshot title: Figure 2 – Ansible Install Verification"
  sleep 2

  print_figure2_block

  capture_screenshot_with_available_tool || true

  printf '\n'
  pass "Activity 2 Figure 2 verification workflow complete."
  info "Screenshot path: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
  info "Text evidence path: ${ACTIVITY2_FIGURE2_OUTPUT}"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      ;;
    "")
      run_verification
      ;;
    *)
      fail "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
}

main "$@"
