#!/usr/bin/env bash
# ==============================================================================
# evidence.sh
# ==============================================================================
#
# Shared evidence/log management helpers for Lab 4 automation scripts.
#
# Purpose:
#  - Provide reusable helpers for evidence directory creation
#  - Archive existing evidence files before new evidence is generated
#  - Prevent accidental overwrite of professor-facing evidence artifacts
#  - Keep evidence behavior consistent across validation and verification scripts
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by scripts such as validate-connectivity.sh and
#    verify-control-node.sh.
#  - Output is handled through lib/common.sh.
#  - This file manages evidence files, not activity-specific validation logic.
#
# RICE Framework:
#  - Reproducibility: Evidence files are created in a predictable structure.
#  - Idempotency: Existing evidence is archived instead of overwritten.
#  - Composability: Multiple scripts can reuse the same evidence helpers.
#  - Evolvability: Future evidence types can reuse the same archive logic.
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
#  - This library was initially shaped around .log evidence files.
#  - Activity-specific scripts decide what content goes into each evidence file.
#
# ------------------------------------------------------------------------------
#
# Version: 1.1
# Date: 2026-06-12
#
# Changes:
#  - Added generic evidence file archive helper.
#  - Added extension-preserving archive names for .txt, .png, .log, and future files.
#  - Added evidence directory writability checks.
#  - Kept archive_existing_log as a backward-compatible wrapper.
#  - Prepared shared evidence behavior for Activity 2 v2.2 idempotent archiving.
#
# Notes:
#  - Generic evidence archiving should be preferred for new scripts.
#  - Legacy log archiving remains available for existing Activity 1 workflows.
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

evidence_directory_is_writable() {
    local evidence_dir="$1"

    if [[ -z "$evidence_dir" ]]; then
        die "Usage: evidence_directory_is_writable <evidence_dir>"
    fi

    [[ -d "$evidence_dir" && -w "$evidence_dir" ]]
}

require_writable_evidence_directory() {
    local evidence_dir="$1"

    step "Checking evidence directory write access"

    if [[ -z "$evidence_dir" ]]; then
        die "Usage: require_writable_evidence_directory <evidence_dir>"
    fi

    if [[ ! -d "$evidence_dir" ]]; then
        die "Evidence directory does not exist: ${evidence_dir}"
    fi

    if [[ ! -w "$evidence_dir" ]]; then
        fail "Evidence directory is not writable: ${evidence_dir}"
        info "This can happen if a verification script was run with sudo."
        info "Recovery command:"
        info "  sudo chown -R student:student ${evidence_dir}"
        die "Fix evidence directory ownership before continuing"
    fi

    pass "Evidence directory is writable: ${evidence_dir}"
}


# ==============================================================================
# Evidence Name Helpers
# ==============================================================================

get_evidence_file_name() {
    local evidence_file="$1"

    if [[ -z "$evidence_file" ]]; then
        die "Usage: get_evidence_file_name <evidence_file>"
    fi

    basename "$evidence_file"
}

get_evidence_file_stem() {
    local evidence_file="$1"
    local file_name

    if [[ -z "$evidence_file" ]]; then
        die "Usage: get_evidence_file_stem <evidence_file>"
    fi

    file_name="$(basename "$evidence_file")"

    if [[ "$file_name" == *.* ]]; then
        printf '%s\n' "${file_name%.*}"
    else
        printf '%s\n' "$file_name"
    fi
}

get_evidence_file_extension() {
    local evidence_file="$1"
    local file_name

    if [[ -z "$evidence_file" ]]; then
        die "Usage: get_evidence_file_extension <evidence_file>"
    fi

    file_name="$(basename "$evidence_file")"

    if [[ "$file_name" == *.* ]]; then
        printf '%s\n' "${file_name##*.}"
    else
        printf '%s\n' "evidence"
    fi
}


# ==============================================================================
# Evidence Archive Helpers
# ==============================================================================

get_next_attempt_number() {
    local archive_dir="$1"
    local archive_prefix="$2"
    local archive_extension="$3"
    local current_count

    if [[ -z "$archive_dir" || -z "$archive_prefix" || -z "$archive_extension" ]]; then
        die "Usage: get_next_attempt_number <archive_dir> <archive_prefix> <archive_extension>"
    fi

    current_count="$(
        find "$archive_dir" -maxdepth 1 -type f \
            -name "${archive_prefix}-attempt-*.${archive_extension}" 2>/dev/null \
            | wc -l
    )"

    printf '%03d\n' "$(( current_count + 1 ))"
}

archive_existing_evidence_file() {
    local evidence_file="$1"
    local archive_dir="$2"
    local archive_prefix="${3:-}"
    local timestamp
    local attempt_number
    local archive_extension
    local archived_file

    step "Checking for existing evidence file"

    if [[ -z "$evidence_file" || -z "$archive_dir" ]]; then
        die "Usage: archive_existing_evidence_file <evidence_file> <archive_dir> [archive_prefix]"
    fi

    if [[ -z "$archive_prefix" ]]; then
        archive_prefix="$(get_evidence_file_stem "$evidence_file")"
    fi

    archive_extension="$(get_evidence_file_extension "$evidence_file")"

    if [[ ! -f "$evidence_file" ]]; then
        pass "No existing evidence file found. A new one will be created."
        return 0
    fi

    mkdir -p "$archive_dir" || die "Failed to create archive directory: ${archive_dir}"

    if [[ ! -w "$archive_dir" ]]; then
        fail "Archive directory is not writable: ${archive_dir}"
        info "This can happen if evidence files were created with sudo."
        info "Recovery command:"
        info "  sudo chown -R student:student ${archive_dir}"
        die "Fix archive directory ownership before continuing"
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    attempt_number="$(get_next_attempt_number "$archive_dir" "$archive_prefix" "$archive_extension")"
    archived_file="${archive_dir}/${archive_prefix}-attempt-${attempt_number}-${timestamp}.${archive_extension}"

    info "Existing evidence file found: ${evidence_file}"
    info "Archiving old evidence to: ${archived_file}"

    mv "$evidence_file" "$archived_file" || die "Failed to archive existing evidence file"

    pass "Previous evidence file archived successfully"
}

archive_existing_evidence_files() {
    local archive_dir="$1"
    shift

    step "Checking for existing evidence files"

    if [[ -z "$archive_dir" || "$#" -eq 0 ]]; then
        die "Usage: archive_existing_evidence_files <archive_dir> <evidence_file> [evidence_file...]"
    fi

    mkdir -p "$archive_dir" || die "Failed to create archive directory: ${archive_dir}"

    local evidence_file
    for evidence_file in "$@"; do
        archive_existing_evidence_file "$evidence_file" "$archive_dir"
    done
}

archive_existing_log() {
    local evidence_file="$1"
    local archive_dir="$2"
    local log_prefix="$3"

    step "Checking for existing evidence log"

    if [[ -z "$evidence_file" || -z "$archive_dir" || -z "$log_prefix" ]]; then
        die "Usage: archive_existing_log <evidence_file> <archive_dir> <log_prefix>"
    fi

    archive_existing_evidence_file "$evidence_file" "$archive_dir" "$log_prefix"
}


# ==============================================================================
# Evidence Reporting Helpers
# ==============================================================================

show_evidence_location() {
    local evidence_file="$1"
    local archive_dir="$2"

    step "Evidence file locations"

    if [[ -z "$evidence_file" || -z "$archive_dir" ]]; then
        die "Usage: show_evidence_location <evidence_file> <archive_dir>"
    fi

    info "Current evidence file: ${evidence_file}"
    info "Archive directory: ${archive_dir}"

    if [[ -f "$evidence_file" ]]; then
        pass "Current evidence file exists: ${evidence_file}"
    else
        warn "Current evidence file does not exist yet: ${evidence_file}"
    fi
}# ==============================================================================
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
