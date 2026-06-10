#!/usr/bin/env bash
# ================================================================================
# common.sh
# ================================================================================
#
# Shared output and safety helpers for infrastructure automation scripts.
#
# Purpose:
#  - Provide consistent, color-coded terminal output
#  - Separate neutral progress messages from check/result messages
#  - Provide reusable safety checks for root access and required commands
#  - Keep logging simple and reusable across Lab 4 scripts
#
# Design:
#  - Use step/info for general workflow output
#  - Use pass/warn/fail only for check or result-style output
#  - Use die for fatal errors that should stop script execution
#  - Disable colors automatically when stdout is not a terminal
#
# RICE Framework:
#  - Reproducibility: Every script uses the same output/check behavior.
#  - Idempotency: Helper checks reduce accidental destructive behavior.
#  - Composability: This file can be sourced by health, bootstrap, and validation scripts.
#  - Evolvability: New helper functions can be added here without rewriting every script.
#
# Author:
#  - Jared Husson
#
# ================================================================================


# ================================================================================
# Source Guard
# ================================================================================
#
# Purpose:
#  - Prevents this file from being loaded more than once in the same shell session.
#
# Notes:
#  - This is useful when multiple libraries source common.sh.
# ================================================================================

if [[ -n "${LAB4_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi

LAB4_COMMON_SH_LOADED="true"


# ================================================================================
# Color Initialization
# ================================================================================

init_colors() {
    if [[ -t 1 ]]; then
        RED=$'\033[0;31m'
        YELLOW=$'\033[1;33m'
        GREEN=$'\033[0;32m'
        BLUE=$'\033[0;34m'
        CYAN=$'\033[0;36m'
        BOLD=$'\033[1m'
        NC=$'\033[0m'
    else
        RED=""
        YELLOW=""
        GREEN=""
        BLUE=""
        CYAN=""
        BOLD=""
        NC=""
    fi
}


# ================================================================================
# General Output Helpers
# ================================================================================

step() {
    printf '\n%s%s==> %s%s\n' "$BOLD" "$CYAN" "$*" "$NC"
}

info() {
    printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"
}


# ================================================================================
# Check / Result Output Helpers
# ================================================================================

pass() {
    printf '%s[PASS]%s %s\n' "$GREEN" "$NC" "$*"
}

warn() {
    printf '%s[WARN]%s %s\n' "$YELLOW" "$NC" "$*"
}

fail() {
    printf '%s[FAIL]%s %s\n' "$RED" "$NC" "$*"
}

die() {
    fail "$*"
    exit 1
}


# ================================================================================
# Safety Helpers
# ================================================================================

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "This script must be run with sudo or as root."
    fi

    pass "Root privileges confirmed."
}

require_command() {
    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        pass "Required command found: ${command_name}"
    else
        die "Required command not found: ${command_name}"
    fi
}

require_file() {
    local file_path="$1"

    if [[ -f "$file_path" ]]; then
        pass "Required file found: ${file_path}"
    else
        die "Required file not found: ${file_path}"
    fi
}

run_or_die() {
    local description="$1"
    shift

    info "$description"
    "$@" || die "Command failed: $description"
}


# ================================================================================
# Initialization
# ================================================================================

init_colors
