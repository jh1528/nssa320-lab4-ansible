#!/usr/bin/env bash
# ==============================================================================
# verify-control-node.sh
# ==============================================================================
#
# Activity:
#  - NSSA320 Lab 4 Activity 2
#
# Version:
#  - v2.2
#
# Purpose:
#  - Verify the RHEL 8 Ansible control node setup for Activity 2.
#  - Confirm required Red Hat, repository, package, and command state.
#  - Generate professor-facing Figure 2 evidence.
#  - Archive previous Activity 2 evidence before generating new evidence.
#
# Important:
#  - Run this script as the normal student user.
#  - Do NOT run this script with sudo.
#  - setup-control-node.sh --apply performs sudo-required setup work.
#  - This script verifies state and generates evidence only.
#
# RICE Notes:
#  - Reproducibility: verification commands are consistent across runs.
#  - Idempotency: existing evidence is archived before new evidence is generated.
#  - Composability: shared config and library helpers are sourced.
#  - Evolvability: future evidence types can be added to the archive list.
#
# Version Notes:
#  - v2.1.3 added root/sudo guard and evidence directory write checks.
#  - v2.2 adds idempotent evidence archiving for text logs and screenshots.
#
# ==============================================================================


# ==============================================================================
# Strict mode
# ==============================================================================

set -u
set -o pipefail


# ==============================================================================
# Root / sudo guard
# ==============================================================================

if [[ "${EUID}" -eq 0 ]]; then
    echo "[FAIL] verify-control-node.sh must not be run as root or with sudo."
    echo "[INFO] Run this script as the normal student user."
    echo "[INFO] setup-control-node.sh --apply is the sudo-required setup workflow."
    exit 1
fi


# ==============================================================================
# Repository paths
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT" || {
    echo "[FAIL] Could not change to repository root: ${REPO_ROOT}"
    exit 1
}


# ==============================================================================
# Source shared files
# ==============================================================================

if [[ ! -f "lib/common.sh" ]]; then
    echo "[FAIL] Missing required library: lib/common.sh"
    exit 1
fi

source "lib/common.sh"

if [[ -f "config/lab4.conf" ]]; then
    source "config/lab4.conf"
else
    warn "Optional config not found: config/lab4.conf"
fi

if [[ ! -f "config/activity2.conf" ]]; then
    die "Missing required config: config/activity2.conf"
fi

source "config/activity2.conf"

if [[ ! -f "lib/redhat.sh" ]]; then
    die "Missing required library: lib/redhat.sh"
fi

source "lib/redhat.sh"

if [[ -f "lib/packages.sh" ]]; then
    source "lib/packages.sh"
else
    warn "Optional library not found: lib/packages.sh"
fi


# ==============================================================================
# Defaults from Activity 2 config
# ==============================================================================

ACTIVITY2_EVIDENCE_DIR="${ACTIVITY2_EVIDENCE_DIR:-evidence/activity2}"
ACTIVITY2_ARCHIVE_DIR="${ACTIVITY2_ARCHIVE_DIR:-${ACTIVITY2_EVIDENCE_DIR}/archive}"

ACTIVITY2_VERIFY_OUTPUT="${ACTIVITY2_VERIFY_OUTPUT:-${ACTIVITY2_EVIDENCE_DIR}/control-node-verification.txt}"
ACTIVITY2_FIGURE2_OUTPUT="${ACTIVITY2_FIGURE2_OUTPUT:-${ACTIVITY2_EVIDENCE_DIR}/figure2-terminal-output.txt}"
ACTIVITY2_FIGURE2_SCREENSHOT="${ACTIVITY2_FIGURE2_SCREENSHOT:-${ACTIVITY2_EVIDENCE_DIR}/figure2-ansible-install-verification.png}"

ACTIVITY2_SCREENSHOT_DELAY_SECONDS="${ACTIVITY2_SCREENSHOT_DELAY_SECONDS:-5}"
ACTIVITY2_REQUIRED_REPO_KEYWORD="${ACTIVITY2_REQUIRED_REPO_KEYWORD:-codeready-builder}"
ACTIVITY2_DEPRECATED_REPO_KEYWORD="${ACTIVITY2_DEPRECATED_REPO_KEYWORD:-ansible-2}"

FAILURES=0


# ==============================================================================
# Failure tracking
# ==============================================================================

record_failure() {
    FAILURES="$((FAILURES + 1))"
}


# ==============================================================================
# Evidence helpers
# ==============================================================================

prepare_activity2_evidence_directories() {
    step "Preparing Activity 2 evidence directories"

    mkdir -p "$ACTIVITY2_EVIDENCE_DIR" || die "Failed to create evidence directory: ${ACTIVITY2_EVIDENCE_DIR}"
    mkdir -p "$ACTIVITY2_ARCHIVE_DIR" || die "Failed to create archive directory: ${ACTIVITY2_ARCHIVE_DIR}"

    if [[ ! -w "$ACTIVITY2_EVIDENCE_DIR" ]]; then
        fail "Activity 2 evidence directory is not writable: ${ACTIVITY2_EVIDENCE_DIR}"
        info "This can happen if verification was previously run with sudo."
        info "Recovery command:"
        info "  sudo chown -R student:student ${ACTIVITY2_EVIDENCE_DIR}"
        die "Fix evidence directory ownership before continuing"
    fi

    if [[ ! -w "$ACTIVITY2_ARCHIVE_DIR" ]]; then
        fail "Activity 2 archive directory is not writable: ${ACTIVITY2_ARCHIVE_DIR}"
        info "This can happen if verification was previously run with sudo."
        info "Recovery command:"
        info "  sudo chown -R student:student ${ACTIVITY2_EVIDENCE_DIR}"
        die "Fix evidence archive ownership before continuing"
    fi

    pass "Evidence directory ready: ${ACTIVITY2_EVIDENCE_DIR}"
    pass "Archive directory ready: ${ACTIVITY2_ARCHIVE_DIR}"
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

    mv "$evidence_file" "$archive_path" || die "Failed to archive evidence file: ${evidence_file}"

    pass "Archived previous evidence: ${archive_path}"
}

archive_activity2_evidence() {
    step "Archiving existing Activity 2 evidence"

    archive_existing_evidence_file "$ACTIVITY2_VERIFY_OUTPUT" "$ACTIVITY2_ARCHIVE_DIR"
    archive_existing_evidence_file "$ACTIVITY2_FIGURE2_OUTPUT" "$ACTIVITY2_ARCHIVE_DIR"
    archive_existing_evidence_file "$ACTIVITY2_FIGURE2_SCREENSHOT" "$ACTIVITY2_ARCHIVE_DIR"

    pass "Activity 2 evidence archive check complete"
}


# ==============================================================================
# Verification helpers
# ==============================================================================

verify_required_commands() {
    local command_name

    step "Checking Activity 2 required commands"

    for command_name in "${ACTIVITY2_REQUIRED_COMMANDS[@]}"; do
        if command -v "$command_name" >/dev/null 2>&1; then
            pass "Required command found: ${command_name}"
        else
            fail "Required command not found: ${command_name}"
            record_failure
        fi
    done
}

verify_required_packages() {
    local package_name

    step "Checking Activity 2 required packages"

    for package_name in "${ACTIVITY2_REQUIRED_PACKAGES[@]}"; do
        if rpm -q "$package_name" >/dev/null 2>&1; then
            pass "Required package installed: ${package_name}"
        else
            fail "Required package not installed: ${package_name}"
            record_failure
        fi
    done
}

verify_redhat_state() {
    step "Running Red Hat and repository checks"

    check_rhel_release || record_failure
    check_subscription_manager || record_failure
    check_subscription_identity || record_failure
    check_subscription_status || record_failure
    check_codeready_builder_enabled || record_failure
    check_deprecated_ansible_engine_repo_not_enabled || record_failure
}

capture_figure2_text_evidence() {
    step "Capturing Figure 2 terminal text evidence"

    {
        echo "Figure 2 - Ansible Install Verification"
        echo "Activity: ${ACTIVITY2_NAME:-Setting Up the Ansible Control Node}"
        echo "Version: ${ACTIVITY2_VERSION:-v2.2}"
        echo
        echo "Command: hostname"
        hostname
        echo
        echo "Command: date"
        date
        echo
        echo "Command: ansible --version"
        ansible --version
    } | tee "$ACTIVITY2_FIGURE2_OUTPUT"

    if [[ -s "$ACTIVITY2_FIGURE2_OUTPUT" ]]; then
        pass "Figure 2 text evidence written: ${ACTIVITY2_FIGURE2_OUTPUT}"
    else
        fail "Figure 2 text evidence was not created correctly"
        record_failure
    fi
}

check_graphical_environment() {
    step "Checking graphical screenshot environment"

    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        warn "No DISPLAY or WAYLAND_DISPLAY detected."
        warn "Automated screenshot capture may not work in this session."
        return 1
    fi

    info "DISPLAY=${DISPLAY:-not-set}"
    info "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-not-set}"
    info "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-not-set}"

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        warn "Wayland session detected. Some screenshot tools may behave differently."
    fi

    pass "Graphical session variables detected"
    return 0
}

capture_figure2_screenshot() {
    local screenshot_tool_used=""

    step "Capturing Figure 2 screenshot"

    if ! check_graphical_environment; then
        warn "Skipping automated screenshot because graphical environment was not detected."
        warn "Manual fallback: capture Figure 2 screenshot yourself and save it as:"
        warn "  ${ACTIVITY2_FIGURE2_SCREENSHOT}"
        return 0
    fi

    info "Screenshot will be captured after ${ACTIVITY2_SCREENSHOT_DELAY_SECONDS} seconds."
    info "Make sure the terminal shows hostname, date, and ansible --version output."
    sleep "$ACTIVITY2_SCREENSHOT_DELAY_SECONDS"

    if command -v gnome-screenshot >/dev/null 2>&1; then
        if gnome-screenshot -f "$ACTIVITY2_FIGURE2_SCREENSHOT" >/dev/null 2>&1; then
            screenshot_tool_used="gnome-screenshot"
        else
            warn "gnome-screenshot failed to save screenshot."
        fi
    fi

    if [[ -z "$screenshot_tool_used" ]] && command -v scrot >/dev/null 2>&1; then
        if scrot "$ACTIVITY2_FIGURE2_SCREENSHOT" >/dev/null 2>&1; then
            screenshot_tool_used="scrot"
        else
            warn "scrot failed to save screenshot."
        fi
    fi

    if [[ -z "$screenshot_tool_used" ]] && command -v import >/dev/null 2>&1; then
        if import -window root "$ACTIVITY2_FIGURE2_SCREENSHOT" >/dev/null 2>&1; then
            screenshot_tool_used="import"
        else
            warn "ImageMagick import failed to save screenshot."
        fi
    fi

    if [[ -n "$screenshot_tool_used" && -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
        pass "Figure 2 screenshot captured with ${screenshot_tool_used}: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
        return 0
    fi

    warn "Automated screenshot capture did not complete."
    warn "Manual fallback: save the screenshot as:"
    warn "  ${ACTIVITY2_FIGURE2_SCREENSHOT}"
    return 0
}

show_activity2_evidence_locations() {
    step "Activity 2 evidence locations"

    info "Verification log: ${ACTIVITY2_VERIFY_OUTPUT}"
    info "Figure 2 text output: ${ACTIVITY2_FIGURE2_OUTPUT}"
    info "Figure 2 screenshot: ${ACTIVITY2_FIGURE2_SCREENSHOT}"
    info "Archive directory: ${ACTIVITY2_ARCHIVE_DIR}"

    if [[ -f "$ACTIVITY2_VERIFY_OUTPUT" ]]; then
        pass "Verification log exists"
    else
        warn "Verification log does not exist yet"
    fi

    if [[ -f "$ACTIVITY2_FIGURE2_OUTPUT" ]]; then
        pass "Figure 2 text output exists"
    else
        warn "Figure 2 text output does not exist yet"
    fi

    if [[ -f "$ACTIVITY2_FIGURE2_SCREENSHOT" ]]; then
        pass "Figure 2 screenshot exists"
    else
        warn "Figure 2 screenshot does not exist yet"
    fi
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    prepare_activity2_evidence_directories
    archive_activity2_evidence

    exec > >(tee "$ACTIVITY2_VERIFY_OUTPUT") 2>&1

    step "Starting Activity 2 control node verification"
    info "Activity: ${ACTIVITY2_NAME:-Setting Up the Ansible Control Node}"
    info "Version: ${ACTIVITY2_VERSION:-v2.2}"
    info "User: $(id -un)"
    info "Repository root: ${REPO_ROOT}"

    verify_redhat_state
    verify_required_commands
    verify_required_packages
    capture_figure2_text_evidence
    capture_figure2_screenshot
    show_activity2_evidence_locations

    if [[ "$FAILURES" -gt 0 ]]; then
        fail "Activity 2 verification completed with ${FAILURES} issue(s)."
        return 1
    fi

    pass "Activity 2 verification completed successfully."
    return 0
}

main "$@"


chmod +x scripts/verify-control-node.sh
