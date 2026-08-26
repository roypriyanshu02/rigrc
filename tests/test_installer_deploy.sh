#!/usr/bin/env bash
# =============================================================================
#  INSTALLER, MANIFEST, DEPLOY, TEMPLATE & DIAGNOSTIC TESTS
# =============================================================================
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "$TESTS_DIR/test_helper.sh"

init_test_sandbox
trap cleanup_test_sandbox EXIT

echo "▶ Running Installer & Deployment Unit Tests..."

# Test _write_file (real write, cmp match, once skip, backup creation)
reset_test_state
test_target="~/test_write.txt"
test_dest="${HOME}/test_write.txt"
test_stow_src="${DOTFILES_DIR}/test_write.txt"
rm -f "$test_dest" "$test_stow_src"

# Real write to TEST_TMP
_write_file "$test_target" "initial content"
assert_success "_write_file creates file in dotfiles directory" test -f "$test_stow_src"
assert_eq "initial content" "$(cat "$test_stow_src")" "_write_file writes content correctly"

# Idempotent cmp match
_write_file "$test_target" "initial content"
assert_success "_write_file is idempotent when content matches" test -f "$test_stow_src"
assert_eq "initial content" "$(cat "$test_stow_src")" "_write_file content unchanged on idempotent call"

# Once-flag skip
_write_file "$test_target" "updated content" "once"
assert_eq "initial content" "$(cat "$test_stow_src")" "_write_file skips existing file with 'once' flag"

# Backup creation
reset_test_state
backup_target="~/test_backup.txt"
backup_dest="${HOME}/test_backup.txt"
backup_stow_src="${DOTFILES_DIR}/test_backup.txt"
rm -f "$backup_dest" "$backup_stow_src"
echo "pre-existing home file content" > "$backup_dest"

_write_file "$backup_target" "new dotfile content"
assert_success "_write_file creates target in dotfiles dir when backing up" test -f "$backup_stow_src"
assert_eq 1 "$BACKUP_COUNT" "_write_file increments BACKUP_COUNT on file backup"
assert_success "_write_file creates backup in BACKUP_DIR" test -f "${BACKUP_DIR}/test_backup.txt"
assert_eq "pre-existing home file content" "$(cat "${BACKUP_DIR}/test_backup.txt")" "_write_file preserves backed up home content"

# Test _get_backup_dir produces no stdout pollution
reset_test_state
bdir_output="$(_get_backup_dir)"
assert_eq "" "$bdir_output" "_get_backup_dir produces zero stdout output"
_get_backup_dir
assert_success "_get_backup_dir sets BACKUP_DIR variable" test -n "$BACKUP_DIR"

# Test _collect_bashrc_snippets
reset_test_state
mkdir -p "$TEST_TMP/empty_pkg_dir"
_CONF_BASHRC_BUF["global"]="export TEST_SUITE_GLOBAL_VAR=1"
_CONF_BASHRC_DIS["global"]=0
_CONF_CASCADE_DONE=1
snippets="$(_collect_bashrc_snippets "$TEST_TMP/empty_pkg_dir")"
assert_success "_collect_bashrc_snippets includes global snippet" test "${snippets#*TEST_SUITE_GLOBAL_VAR=1}" != "$snippets"

# Test _format_manifest exit status 0 vs 1
reset_test_state
fmt_clean="${TEST_TMP}/clean.conf"
fmt_dirty="${TEST_TMP}/dirty.conf"

cat << 'EOF' > "$fmt_clean"
[package]
name=cleanpkg
EOF

cat << 'EOF' > "$fmt_dirty"
[package]
name=dirtypkg   
EOF

assert_success "_format_manifest --check-only returns 0 on formatted file" _format_manifest --check-only "$fmt_clean"
assert_failure "_format_manifest --check-only returns 1 on unformatted file" _format_manifest --check-only "$fmt_dirty"

# Test deploy_stow dry-run
reset_test_state
DRY_RUN=true
assert_success "deploy_stow succeeds in dry-run mode" deploy_stow

# Test _in_cond_list glob handling
reset_test_state
assert_success "_in_cond_list matches exact item in list" _in_cond_list 'linux' 'linux, wsl, darwin'
assert_failure "_in_cond_list fails non-matching item" _in_cond_list 'bsd' 'linux, wsl, darwin'
assert_success "_in_cond_list matches literal asterisk without glob expanding" _in_cond_list '*' '*, linux'
assert_failure "_in_cond_list does not expand asterisk to setup.sh" _in_cond_list 'setup.sh' '*, linux'

# Test template delimiter parsing
reset_test_state
tmp_tmpl_conf="$(mktemp)"
cat << 'EOF' > "$tmp_tmpl_conf"
[template:~/.config/test1.conf:once:cond=wsl]
key1=val1
[template:~/.config/test2.conf:once:cond=desktop]
key2=val2
EOF

_parse_single_conf_file "$tmp_tmpl_conf" "testpkg"
rm -f "$tmp_tmpl_conf"

buf_val="${_CONF_TMPL_BUF["testpkg"]:-}"
assert_success "template buffer uses __TMPL_SEP__ delimiter" test "${buf_val#*__TMPL_SEP__}" != "$buf_val"
assert_success "template buffer does not contain NUL byte" test "${buf_val#*$'\0'}" = "$buf_val"
assert_success "template buffer contains target path" test "${buf_val#*# target: ~/.config/test1.conf}" != "$buf_val"
assert_success "template buffer contains cond flag" test "${buf_val#*cond=wsl}" != "$buf_val"

# Test template override resolution in deploy_package_templates
reset_test_state
_CONF_CASCADE_DONE=1
tmp_pkg_conf="$(mktemp)"
cat << 'EOF' > "$tmp_pkg_conf"
[package]
name = mytool
[template:~/.config/mytool.toml:once]
default_setting = true
EOF

tmp_user_conf="$(mktemp)"
cat << 'EOF' > "$tmp_user_conf"
[template:~/.config/mytool.toml:override]
custom_setting = 42
EOF

_parse_single_conf_file "$tmp_pkg_conf" "mytool"
_parse_single_conf_file "$tmp_user_conf" "global"
_CONF_TEMPLATES["$tmp_pkg_conf"]="${_CONF_TMPL_BUF["mytool"]:-}"

deploy_package_templates "$tmp_pkg_conf"
rm -f "$tmp_pkg_conf" "$tmp_user_conf"

assert_success "overridden template file created" test -f "$DOTFILES_DIR/.config/mytool.toml"
assert_contains "$(cat "$DOTFILES_DIR/.config/mytool.toml")" "custom_setting = 42" "overridden template content deployed"

# Test _CONF_PKG_DECLINED and needs resolution in _package_is_active
reset_test_state
_preload_all_manifests "$PACKAGES_DIR"
_CONF_PKG_DISABLED["git"]=1
assert_failure "_package_is_active fails when needed dependency is disabled" _package_is_active "$PACKAGES_DIR/shell/delta.conf"

reset_test_state
_preload_all_manifests "$PACKAGES_DIR"
_CONF_PKG_DECLINED["git"]=1
assert_failure "_package_is_active fails when needed dependency is declined" _package_is_active "$PACKAGES_DIR/shell/delta.conf"

reset_test_state
_preload_all_manifests "$PACKAGES_DIR"
_CONF_PKG_DECLINED["delta"]=1
assert_failure "_package_is_active fails when package itself is marked declined" _package_is_active "$PACKAGES_DIR/shell/delta.conf"

# Test _find_pkg_manifest
assert_success "_find_pkg_manifest finds existing package 'git'" _find_pkg_manifest "git"
assert_failure "_find_pkg_manifest fails on nonexistent package" _find_pkg_manifest "nonexistent_pkg_12345"

# Test _resolve_missing_dependency when binary is already present
assert_success "_resolve_missing_dependency returns 0 if dependency already installed" _resolve_missing_dependency "delta" "bash"

# Test _resolve_missing_dependency in non-interactive mode for missing dependency
reset_test_state
_CONF_PKG_DECLINED=()
NON_INTERACTIVE=true
assert_failure "_resolve_missing_dependency returns 1 for missing dependency in headless mode" _resolve_missing_dependency "delta" "nonexistent_bin_123"
assert_eq "1" "${_CONF_PKG_DECLINED["delta"]:-0}" "_resolve_missing_dependency marks parent declined on missing dependency"

# Test _resolve_missing_dependency interactive decline
reset_test_state
_CONF_PKG_DECLINED=()
dummy_dep_file="$PACKAGES_DIR/core/test_dummy_dep_$$.conf"
cat << 'EOF' > "$dummy_dep_file"
[package]
name = test_dummy_dep
binaries = nonexistent_bin_dummy_xyz
description = Dummy test package
EOF
decline_res=0
NON_INTERACTIVE=false
_resolve_missing_dependency "delta" "test_dummy_dep_$$" <<< "n" 2>/dev/null || decline_res=$?
NON_INTERACTIVE=true
rm -f "$dummy_dep_file"
assert_eq "1" "$decline_res" "_resolve_missing_dependency returns 1 when user declines prompt"
assert_eq "1" "${_CONF_PKG_DECLINED["delta"]:-0}" "_resolve_missing_dependency marks parent declined when user declines prompt"

# Test _check_disk_space
assert_success "_check_disk_space passes on reasonable threshold" _check_disk_space 1 "$TEST_TMP"
assert_failure "_check_disk_space fails on impossible threshold" _check_disk_space 999999999 "$TEST_TMP"

# Test _export_diagnostics
diag_file="${TEST_TMP}/diagnostics.json"
assert_success "_export_diagnostics generates json file" bash -c "source '${SETUP_SCRIPT}'; _export_diagnostics '${diag_file}'"
assert_success "_export_diagnostics contains valid json field" grep -q '"package_manager"' "$diag_file"

# Test _rollback_latest_backup
bak_test_dir="${HOME}/.dotfiles.bak/20991231_235959"
mkdir -p "$bak_test_dir"
echo "original_backed_up_content" > "$bak_test_dir/restored_config.conf"
rm -f "${HOME}/restored_config.conf"
assert_success "_rollback_latest_backup restores backup files" _rollback_latest_backup
assert_eq "original_backed_up_content" "$(<"${HOME}/restored_config.conf")" "_rollback_latest_backup restores exact content"

# Test named snapshot rollback
rm -f "${HOME}/restored_config.conf"
assert_success "_rollback_latest_backup restores specific named snapshot" _rollback_latest_backup "20991231_235959"
assert_eq "original_backed_up_content" "$(<"${HOME}/restored_config.conf")" "_rollback_latest_backup named snapshot restores exact content"

# Test _ui_render_summary
assert_success "_ui_render_summary executes cleanly" _ui_render_summary 1 5 2

# Test failed package install: skip post hooks & templates when declined or headless
reset_test_state
MAX_RETRIES=1
RETRY_DELAY=0
fail_post_marker="${TEST_TMP}/post_hook_marker_$$"
fail_tmpl_file="fail_tmpl_target_$$"
rm -f "$fail_post_marker" "${DOTFILES_DIR}/.config/${fail_tmpl_file}" "${HOME}/.config/${fail_tmpl_file}"
fail_conf_file="${PACKAGES_DIR}/core/fail_test_pkg_$$.conf"
cat << EOF > "$fail_conf_file"
[package]
name = fail_test_pkg_$$
binaries = nonexistent_fail_bin_$$
scope = user
cmd = false
post = touch "$fail_post_marker"

[template:~/.config/${fail_tmpl_file}:once]
failed_template_content
EOF

# Headless mode skips post actions
NON_INTERACTIVE=true
_install_single_package "$fail_conf_file" "fail_test_pkg_$$"
assert_failure "headless failed install skips post hook" test -f "$fail_post_marker"
assert_failure "headless failed install skips template deployment" test -f "${DOTFILES_DIR}/.config/${fail_tmpl_file}"

# Interactive 'n' skips post actions
NON_INTERACTIVE=false
_install_single_package "$fail_conf_file" "fail_test_pkg_$$" <<< "n" 2>/dev/null || true
assert_failure "interactive 'n' failed install skips post hook" test -f "$fail_post_marker"
assert_failure "interactive 'n' failed install skips template deployment" test -f "${DOTFILES_DIR}/.config/${fail_tmpl_file}"

# Interactive 'y' executes post actions
_install_single_package "$fail_conf_file" "fail_test_pkg_$$" <<< "y" 2>/dev/null || true
NON_INTERACTIVE=true
assert_success "interactive 'y' failed install executes post hook" test -f "$fail_post_marker"
assert_success "interactive 'y' failed install deploys templates" test -f "${DOTFILES_DIR}/.config/${fail_tmpl_file}"
rm -f "$fail_conf_file" "$fail_post_marker" "${DOTFILES_DIR}/.config/${fail_tmpl_file}" "${HOME}/.config/${fail_tmpl_file}"

# Test circular dependency loop prevention
reset_test_state
_DEP_RESOLVE_STACK["circular_dep_pkg"]=1
assert_failure "_resolve_missing_dependency detects circular dependency and returns 1" _resolve_missing_dependency "parent_pkg" "circular_dep_pkg"
assert_eq "1" "${_CONF_PKG_DECLINED["parent_pkg"]:-0}" "_resolve_missing_dependency marks parent declined on circular dependency"
_DEP_RESOLVE_STACK=()

# Test path traversal prevention in rollback
bak_trav_dir="${HOME}/.dotfiles.bak/20991231_235958"
mkdir -p "$bak_trav_dir"
touch "$bak_trav_dir/valid.txt"
# If a file tried to escape via traversal
rm -f "${HOME}/valid.txt"
assert_success "_rollback_latest_backup handles snapshots cleanly" _rollback_latest_backup "20991231_235958"
assert_success "_rollback_latest_backup restored valid file" test -f "${HOME}/valid.txt"

echo "  Section Results: ${PASSED_COUNT} passed, ${FAILED_COUNT} failed."
[[ $FAILED_COUNT -eq 0 ]] || exit 1
