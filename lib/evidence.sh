#!/usr/bin/env bash
# ==============================================================================
# evidence.sh
# ==============================================================================
#
# Shared evidence/log management helpers for Lab 4 automation scripts.
#
# Purpose:
#  - Provide reusable helpers for evidence directory creation
#  - Archive existing evidence logs before new logs are generated
#  - Prevent accidental overwrite of professor-facing evidence files
#  - Keep evidence behavior consistent across validation scripts
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by scripts such as validate-connectivity.sh.
#  - Output is handled through lib/common.sh.
#  - This file manages evidence files, not connectivity logic itself.
#
# RICE Framework:
#  - Reproducibility: Evidence files are created in a predictable structure.
#  - Idempotency: Existing logs are archived instead of overwritten.
#  - Composability: Multiple validation scripts can reuse the same archive logic.
#  - Evolvability: Future evidence types can reuse the same helper functions.
#
# Dependencies:
#  - lib/common.sh must be sourced before this file is used.
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
#  - Added evidence directory preparation helper.
#  - Added reusable evidence log archive helper.
#  - Added attempt-number and timestamp-based archive naming.
#  - Added basic evidence file existence helper.
#
# Notes:
#  - This library is intentionally generic.
#  - Activity-specific scripts decide what content goes into each evidence file.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB4_EVIDENCE_SH_LOADED:-}" ]]; then
    return 0
fi

LAB4_EVIDENCE_SH_LOADED="true"


# ==============================================================================
# Evidence Directory Helpers
# ==============================================================================

prepare_evidence_directories() {
    local evidence_dir="$1"
    local archive_dir="$2"

    step "Preparing evidence directories"

    if [[ -z "$evidence_dir" || -z "$archive_dir" ]]; then
        die "Usage: prepare_evidence_directories <evidence_dir> <archive_dir>"
    fi

    mkdir -p "$evidence_dir" || die "Failed to create evidence directory: ${evidence_dir}"
    mkdir -p "$archive_dir" || die "Failed to create archive directory: ${archive_dir}"

    pass "Evidence directory ready: ${evidence_dir}"
    pass "Archive directory ready: ${archive_dir}"
}

evidence_file_exists() {
    local evidence_file="$1"

    if [[ -z "$evidence_file" ]]; then
        die "Usage: evidence_file_exists <evidence_file>"
    fi

    [[ -f "$evidence_file" ]]
}


# ==============================================================================
# Evidence Archive Helpers
# ==============================================================================

get_next_attempt_number() {
    local archive_dir="$1"
    local log_prefix="$2"
    local current_count

    if [[ -z "$archive_dir" || -z "$log_prefix" ]]; then
        die "Usage: get_next_attempt_number <archive_dir> <log_prefix>"
    fi

    current_count="$(
        find "$archive_dir" -maxdepth 1 -type f -name "${log_prefix}-attempt-*.log" 2>/dev/null \
            | wc -l
    )"

    printf '%03d\n' "$(( current_count + 1 ))"
}

archive_existing_log() {
    local evidence_file="$1"
    local archive_dir="$2"
    local log_prefix="$3"
    local timestamp
    local attempt_number
    local archived_log

    step "Checking for existing evidence log"

    if [[ -z "$evidence_file" || -z "$archive_dir" || -z "$log_prefix" ]]; then
        die "Usage: archive_existing_log <evidence_file> <archive_dir> <log_prefix>"
    fi

    if [[ ! -f "$evidence_file" ]]; then
        pass "No existing evidence log found. A new one will be created."
        return 0
    fi

    mkdir -p "$archive_dir" || die "Failed to create archive directory: ${archive_dir}"

    timestamp="$(date +%Y%m%d-%H%M%S)"
    attempt_number="$(get_next_attempt_number "$archive_dir" "$log_prefix")"
    archived_log="${archive_dir}/${log_prefix}-attempt-${attempt_number}-${timestamp}.log"

    info "Existing evidence log found: ${evidence_file}"
    info "Archiving old log to: ${archived_log}"

    mv "$evidence_file" "$archived_log" || die "Failed to archive existing evidence log"

    pass "Previous evidence log archived successfully"
}

show_evidence_location() {
    local evidence_file="$1"
    local archive_dir="$2"

    step "Evidence file locations"

    info "Current evidence file: ${evidence_file}"
    info "Archive directory: ${archive_dir}"

    if [[ -f "$evidence_file" ]]; then
        pass "Current evidence file exists: ${evidence_file}"
    else
        warn "Current evidence file does not exist yet: ${evidence_file}"
    fi
}
