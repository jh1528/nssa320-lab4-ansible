#!/usr/bin/env bash
# ==============================================================================
# privilege.sh
# ==============================================================================
#
# Shared privilege escalation helpers for NSSA320 Lab 4 Activity 4.
#
# Purpose:
# - Provide reusable functions for Activity 4 setup and verification scripts.
# - Keep sudoers, inventory, and ansible.cfg logic out of the top-level scripts.
# - Support repeatable, evidence-friendly privileged escalation automation.
#
# Scope:
# - Activity 4 only.
# - This library defines functions only.
# - It does not run setup or verification by itself.
#
# Dependencies:
# - config/lab4.conf should be sourced before config/activity4.conf.
# - config/activity4.conf must be sourced before this library.
# - lib/common.sh must be sourced before this library.
#
# Security Note:
# - Do not store passwords, tokens, private keys, or secrets in this file.
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 4.0
# Date: 2026-06-22
#
# Changes:
# - Added Activity 4 required command checks.
# - Added inventory pre-check helper.
# - Added control-node sudoers installation and verification helpers.
# - Added managed-host sudoers deployment helpers.
# - Added ansible.cfg creation and verification helpers.
#
# ==============================================================================

# ==============================================================================
# Source Guard
# ==============================================================================
if [[ -n "${LAB4_PRIVILEGE_SH_LOADED:-}" ]]; then
    return 0
fi
LAB4_PRIVILEGE_SH_LOADED="true"

# ==============================================================================
# Dependency Check
# ==============================================================================
if ! declare -F step >/dev/null 2>&1; then
    printf '[FAIL] lib/common.sh must be sourced before lib/privilege.sh\n' >&2
    return 1
fi

# ==============================================================================
# Activity 4 Context / Required Commands
# ==============================================================================
activity4_show_context() {
    step "Activity 4 context"
    info "Activity: ${ACTIVITY4_NAME}"
    info "Version: ${ACTIVITY4_VERSION}"
    info "Inventory: ${ACTIVITY4_INVENTORY_FILE}"
    info "Control sudoers file: ${ACTIVITY4_CONTROL_SUDOERS_FILE}"
    info "Managed sudoers file: ${ACTIVITY4_MANAGED_SUDOERS_FILE}"
    info "Ansible config: ${ACTIVITY4_ANSIBLE_CFG}"
}

activity4_check_required_commands() {
    step "Checking Activity 4 required commands"

    local command_name
    for command_name in "${ACTIVITY4_REQUIRED_COMMANDS[@]}"; do
        require_command "$command_name"
    done
}

# ==============================================================================
# Inventory Pre-Check
# ==============================================================================
activity4_precheck_inventory() {
    step "Pre-checking Activity 3 inventory data"

    require_file "$ACTIVITY4_INVENTORY_FILE"

    local expected_item
    local expected_items=(
        "[${ACTIVITY4_UBUNTU_GROUP}]"
        "[${ACTIVITY4_ROCKY_GROUP}]"
        "ubuntu"
        "ansible1"
        "ansible2"
    )

    for expected_item in "${expected_items[@]}"; do
        if grep -Fxq "$expected_item" "$ACTIVITY4_INVENTORY_FILE"; then
            pass "Inventory contains expected entry: ${expected_item}"
        else
            die "Inventory pre-check failed. Missing expected entry: ${expected_item}"
        fi
    done

    pass "Inventory pre-check completed."
}

# ==============================================================================
# Local Control Node Sudoers Helpers
# ==============================================================================
activity4_install_control_sudoers() {
    step "Installing control-node password-less sudoers file"

    printf '%s\n' "$ACTIVITY4_CONTROL_SUDOERS_CONTENT" \
        | sudo tee "$ACTIVITY4_CONTROL_SUDOERS_FILE" >/dev/null \
        || die "Failed to write ${ACTIVITY4_CONTROL_SUDOERS_FILE}"

    sudo chown root:root "$ACTIVITY4_CONTROL_SUDOERS_FILE" \
        || die "Failed to set owner on ${ACTIVITY4_CONTROL_SUDOERS_FILE}"

    sudo chmod "$ACTIVITY4_SUDOERS_MODE" "$ACTIVITY4_CONTROL_SUDOERS_FILE" \
        || die "Failed to set mode on ${ACTIVITY4_CONTROL_SUDOERS_FILE}"

    sudo visudo -cf "$ACTIVITY4_CONTROL_SUDOERS_FILE" \
        || die "visudo validation failed for ${ACTIVITY4_CONTROL_SUDOERS_FILE}"

    pass "Control-node sudoers file installed and validated."
}

activity4_verify_control_sudo() {
    step "Verifying control-node password-less sudo"

    sudo -n ls -ld /root >/dev/null \
        || die "Control-node password-less sudo verification failed."

    pass "Control-node password-less sudo works."
}

# ==============================================================================
# Managed Host Sudoers Helpers
# ==============================================================================
activity4_create_temp_ansible_sudoers_file() {
    step "Creating temporary ansible sudoers source file on control node"

    local temp_sudoers_file="${ACTIVITY4_TEMP_SUDOERS_FILE:-/tmp/sudoers}"

    printf '%s\n' "$ACTIVITY4_MANAGED_SUDOERS_CONTENT" > "$temp_sudoers_file" \
        || die "Failed to write ${temp_sudoers_file}"

    chmod 0644 "$temp_sudoers_file" \
        || die "Failed to set mode on ${temp_sudoers_file}"

    pass "Temporary ansible sudoers source file ready: ${temp_sudoers_file}"
}

activity4_deploy_ansible_sudoers_to_group() {
    local target_group="$1"
    local temp_sudoers_file="${ACTIVITY4_TEMP_SUDOERS_FILE:-/tmp/sudoers}"

    if [[ -z "$target_group" ]]; then
        die "Usage: activity4_deploy_ansible_sudoers_to_group <inventory_group>"
    fi

    step "Deploying ansible sudoers file to ${target_group}"

    require_file "$temp_sudoers_file"

    ansible "$target_group" \
        -i "$ACTIVITY4_INVENTORY_FILE" \
        -u "$ACTIVITY4_REMOTE_USER" \
        -b -k -K \
        -m copy \
        -a "src=${temp_sudoers_file} dest=${ACTIVITY4_MANAGED_SUDOERS_FILE} mode=${ACTIVITY4_SUDOERS_MODE} owner=root group=root validate='visudo -cf %s'" \
        || die "Failed to deploy ansible sudoers file to ${target_group}"

    pass "Ansible sudoers file deployed to ${target_group}."
}

activity4_deploy_student_sudoers_to_managed_hosts() {
    step "Deploying student sudoers file to all managed hosts"

    local student_sudoers_file="${ACTIVITY4_MANAGED_STUDENT_SUDOERS_FILE:-/etc/sudoers.d/student}"
    local student_sudoers_content="${ACTIVITY4_MANAGED_STUDENT_SUDOERS_CONTENT:-${ACTIVITY4_CONTROL_SUDOERS_CONTENT}}"

    ansible "$ACTIVITY4_ALL_GROUP" \
        -i "$ACTIVITY4_INVENTORY_FILE" \
        -u "$ACTIVITY4_REMOTE_USER" \
        --become -K \
        -m copy \
        -a "content='${student_sudoers_content}\n' dest=${student_sudoers_file} owner=root group=root mode=${ACTIVITY4_SUDOERS_MODE} validate='visudo -cf %s'" \
        || die "Failed to deploy student sudoers file to managed hosts"

    pass "Student sudoers file deployed to all managed hosts."
}

activity4_validate_managed_sudoers() {
    step "Validating managed-host sudoers files"

    ansible "$ACTIVITY4_ALL_GROUP" \
        -i "$ACTIVITY4_INVENTORY_FILE" \
        -u "$ACTIVITY4_REMOTE_USER" \
        --become \
        -m command \
        -a "visudo -cf ${ACTIVITY4_MANAGED_SUDOERS_FILE}" \
        || die "Managed ansible sudoers validation failed"

    ansible "$ACTIVITY4_ALL_GROUP" \
        -i "$ACTIVITY4_INVENTORY_FILE" \
        -u "$ACTIVITY4_REMOTE_USER" \
        --become \
        -m command \
        -a "visudo -cf /etc/sudoers.d/student" \
        || die "Managed student sudoers validation failed"

    pass "Managed-host sudoers files validated."
}

# ==============================================================================
# Ansible Configuration Helpers
# ==============================================================================
activity4_write_ansible_cfg() {
    step "Creating Activity 4 ansible.cfg"

    mkdir -p "$ACTIVITY4_LAB_DIR" \
        || die "Failed to create lab directory: ${ACTIVITY4_LAB_DIR}"

    cat > "$ACTIVITY4_ANSIBLE_CFG" <<EOF_CFG
[defaults]
ansible_user=${ACTIVITY4_REMOTE_USER}
ansible_become=true
EOF_CFG

    pass "Ansible configuration ready: ${ACTIVITY4_ANSIBLE_CFG}"
}

activity4_verify_ansible_cfg() {
    step "Verifying Activity 4 ansible.cfg"

    require_file "$ACTIVITY4_ANSIBLE_CFG"

    grep -Fxq "[defaults]" "$ACTIVITY4_ANSIBLE_CFG" \
        || die "Missing [defaults] section in ${ACTIVITY4_ANSIBLE_CFG}"

    grep -Fxq "ansible_user=${ACTIVITY4_REMOTE_USER}" "$ACTIVITY4_ANSIBLE_CFG" \
        || die "Missing ansible_user setting in ${ACTIVITY4_ANSIBLE_CFG}"

    grep -Fxq "ansible_become=true" "$ACTIVITY4_ANSIBLE_CFG" \
        || die "Missing ansible_become setting in ${ACTIVITY4_ANSIBLE_CFG}"

    pass "Ansible configuration contains expected Activity 4 settings."
}

# ==============================================================================
# Final Verification Helpers
# ==============================================================================
activity4_verify_privileged_ansible_command() {
    step "Verifying privileged Ansible command without -b, -k, or -K"

    (
        cd "$ACTIVITY4_LAB_DIR"
        ansible -i "$(basename "$ACTIVITY4_INVENTORY_FILE")" \
            "$ACTIVITY4_ALL_GROUP" \
            -m command \
            -a "ls -ld /root"
    ) || die "Privileged Ansible command failed without interactive flags"

    pass "Privileged Ansible command succeeded without -b, -k, or -K."
}

activity4_verify_idempotent_user_task() {
    step "Verifying idempotent Ansible user task"

    (
        cd "$ACTIVITY4_LAB_DIR"
        ansible -i "$(basename "$ACTIVITY4_INVENTORY_FILE")" \
            "$ACTIVITY4_ALL_GROUP" \
            -m user \
            -a "name=${ACTIVITY4_SERVICE_USER} create_home=yes"
    ) || die "Idempotent user task verification failed"

    pass "Idempotent user task completed."
}
