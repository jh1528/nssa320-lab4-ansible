#!/usr/bin/env bash
#
# NSSA320 Lab 4 - Shared Package Library
# File: lib/packages.sh
#
# Purpose:
#   Provides reusable package-management helper functions for Lab 4 workflows.
#   This file should be sourced by scripts, not executed directly.
#
# Scope:
#   Activity 2 uses this library to update the RHEL 8 control node,
#   install EPEL, install Ansible, and verify required commands.
#   Future activities may reuse this library for additional package checks.
#
# Safety:
#   This library does not run package updates or installs automatically.
#   Runnable scripts must explicitly call these functions.
#
# RICE Notes:
#   Reproducibility - standardizes package checks and install behavior.
#   Idempotency     - checks package state before installing when possible.
#   Composability   - reusable by Activity 2 and future lab activities.
#   Evolvability    - future package requirements can be added here safely.
#
# Version History:
#   v2.0 - Initial package helper library for Activity 2.

# ---------------------------------------------------------------------------
# Safety guard
# ---------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "[FAIL] lib/packages.sh is a shared library and should be sourced, not executed."
  echo "[INFO] Example: source lib/packages.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# Privilege checks
# ---------------------------------------------------------------------------

require_root() {
  step "Checking root privileges"

  if [[ "${EUID}" -ne 0 ]]; then
    fail "This action requires root privileges."
    warn "Run the calling script with sudo when using --apply."
    return 1
  fi

  pass "Running with root privileges."
}

# ---------------------------------------------------------------------------
# Command checks
# ---------------------------------------------------------------------------

check_command_available() {
  local command_name="$1"

  step "Checking required command: ${command_name}"

  if command -v "$command_name" >/dev/null 2>&1; then
    pass "Required command found: ${command_name}"
    return 0
  fi

  fail "Required command not found: ${command_name}"
  return 1
}

check_required_commands() {
  local command_name

  step "Checking required Activity 2 commands"

  for command_name in "${ACTIVITY2_REQUIRED_COMMANDS[@]}"; do
    check_command_available "$command_name"
  done
}

# ---------------------------------------------------------------------------
# Package checks
# ---------------------------------------------------------------------------

check_package_installed() {
  local package_name="$1"

  step "Checking installed package: ${package_name}"

  if rpm -q "$package_name" >/dev/null 2>&1; then
    pass "Package is installed: ${package_name}"
    return 0
  fi

  warn "Package is not installed: ${package_name}"
  return 1
}

install_package_if_missing() {
  local package_name="$1"

  step "Ensuring package is installed: ${package_name}"

  if rpm -q "$package_name" >/dev/null 2>&1; then
    pass "Package already installed: ${package_name}"
    return 0
  fi

  require_root

  info "Installing package: ${package_name}"
  dnf install -y "$package_name"

  pass "Package installation completed: ${package_name}"
}

install_required_packages() {
  local package_name

  step "Installing required Activity 2 packages"

  for package_name in "${ACTIVITY2_REQUIRED_PACKAGES[@]}"; do
    install_package_if_missing "$package_name"
  done
}

# ---------------------------------------------------------------------------
# EPEL helpers
# ---------------------------------------------------------------------------

check_epel_installed() {
  local epel_package="${ACTIVITY2_EPEL_PACKAGE:-epel-release}"

  check_package_installed "$epel_package"
}

install_epel_if_missing() {
  local epel_package="${ACTIVITY2_EPEL_PACKAGE:-epel-release}"
  local epel_url="${ACTIVITY2_EPEL_RPM_URL:?ACTIVITY2_EPEL_RPM_URL is not set}"

  step "Ensuring EPEL is installed"

  if rpm -q "$epel_package" >/dev/null 2>&1; then
    pass "EPEL package already installed: ${epel_package}"
    return 0
  fi

  require_root

  info "Installing EPEL from: ${epel_url}"
  dnf install -y "$epel_url"

  pass "EPEL installation completed."
}

# ---------------------------------------------------------------------------
# System update helper
# ---------------------------------------------------------------------------

dnf_update_system() {
  step "Updating system packages with DNF"

  require_root

  info "Running: dnf update -y"
  dnf update -y

  pass "DNF system update completed."
}

# ---------------------------------------------------------------------------
# Verification helpers
# ---------------------------------------------------------------------------

show_ansible_version() {
  step "Checking Ansible version"

  if command -v ansible >/dev/null 2>&1; then
    ansible --version
    pass "Ansible version displayed successfully."
    return 0
  fi

  fail "Ansible command not found."
  return 1
}

show_python_version() {
  step "Checking Python 3 version"

  if command -v python3 >/dev/null 2>&1; then
    python3 --version
    pass "Python 3 version displayed successfully."
    return 0
  fi

  fail "python3 command not found."
  return 1
}

show_dnf_repolist() {
  step "Showing enabled DNF repositories"

  if command -v dnf >/dev/null 2>&1; then
    dnf repolist
    pass "DNF repository list displayed successfully."
    return 0
  fi

  fail "dnf command not found."
  return 1
}
