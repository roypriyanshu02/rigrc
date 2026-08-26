#!/usr/bin/env bash
# =============================================================================
#  PARSER, CONFIG, STRINGS & SCOPING TESTS
# =============================================================================
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "$TESTS_DIR/test_helper.sh"

init_test_sandbox
trap cleanup_test_sandbox EXIT

echo "▶ Running Parser & String Unit Tests..."

# Test _trim
assert_eq "" "$(_trim "")" "_trim empty string"
assert_eq "foo" "$(_trim "   foo   ")" "_trim strips spaces"
assert_eq "foo" "$(_trim $' \t foo \t ')" "_trim strips spaces and tabs"
assert_eq "bar" "$(_trim $'\n bar \n')" "_trim strips newlines"
assert_eq "bar baz" "$(_trim $' \t bar baz \n ')" "_trim preserves inner space"

# Test _get_arch
arch="$(_get_arch)"
_test_arch_valid() { [[ "$1" =~ ^(x86_64|arm64|unknown|[a-zA-Z0-9_-]+)$ ]]; }
assert_success "_get_arch returns valid arch string ('$arch')" _test_arch_valid "$arch"

# Test _get_opt
assert_eq "git" "$(_get_opt "apt" "apt:git dnf:git-core")" "_get_opt extracts unquoted key:val"
assert_eq "space val" "$(_get_opt "opt" 'apt:git opt:"space val"')" "_get_opt extracts quoted key:val"

# Test _parse_section_header
st="" si="" sm="" sv=0
_parse_section_header "package" st si sm sv
assert_eq "package" "$st" "_parse_section_header package type"
assert_eq "" "$si" "_parse_section_header package empty ident"
assert_eq "append" "$sm" "_parse_section_header package default mod"
assert_eq "0" "$sv" "_parse_section_header package valid code"

_parse_section_header "template:~/.config/git:once" st si sm sv
assert_eq "template" "$st" "_parse_section_header template type"
assert_eq "~/.config/git" "$si" "_parse_section_header template ident"
assert_eq "once" "$sm" "_parse_section_header template mod"
assert_eq "0" "$sv" "_parse_section_header template valid code"

_parse_section_header "template:~/.config/git:once:cond=wsl" st si sm sv
assert_eq "template" "$st" "_parse_section_header template with cond type"
assert_eq "~/.config/git" "$si" "_parse_section_header template with cond ident"
assert_eq "once cond=wsl" "$sm" "_parse_section_header template with cond mod"
assert_eq "0" "$sv" "_parse_section_header template with cond valid code"

_parse_section_header "template:/etc/docker/daemon.json:once:cond=!container:post=sudo systemctl reload docker" st si sm sv
assert_eq "template" "$st" "_parse_section_header template multipart type"
assert_eq "/etc/docker/daemon.json" "$si" "_parse_section_header template multipart ident"
assert_eq "0" "$sv" "_parse_section_header template multipart valid code"

_parse_section_header "template:~/.config/git:disable" st si sm sv
assert_eq "template" "$st" "_parse_section_header template type for :disable"
assert_eq "~/.config/git" "$si" "_parse_section_header template ident for :disable"
assert_eq "disable" "$sm" "_parse_section_header template modifier for :disable"
assert_eq "0" "$sv" "_parse_section_header template valid code for :disable"

_parse_section_header "bashrc:override" st si sm sv
assert_eq "bashrc" "$st" "_parse_section_header bashrc type for :override"
assert_eq "" "$si" "_parse_section_header bashrc ident for :override"
assert_eq "override" "$sm" "_parse_section_header bashrc modifier for :override"
assert_eq "0" "$sv" "_parse_section_header bashrc valid code for :override"

_parse_section_header "config" st si sm sv
assert_eq "config" "$st" "_parse_section_header config section type"
assert_eq "" "$si" "_parse_section_header config empty ident"
assert_eq "append" "$sm" "_parse_section_header config default mod"
assert_eq "0" "$sv" "_parse_section_header config valid code"

_parse_section_header "package:pkg-config" st si sm sv
assert_eq "package" "$st" "_parse_section_header pkg-config type"
assert_eq "pkg-config" "$si" "_parse_section_header pkg-config preserves name"
assert_eq "0" "$sv" "_parse_section_header pkg-config valid code"

_parse_section_header "invalid_section_type_xyz" st si sm sv
assert_eq "1" "$sv" "_parse_section_header invalid header code"

_parse_section_header "package:foo:bar:baz" st si sm sv
assert_eq "1" "$sv" "_parse_section_header invalid header code for excess colons"

# Test _validate_email
assert_success "_validate_email accepts standard email" _validate_email "user@example.com"
assert_success "_validate_email accepts tag email" _validate_email "john.doe+tag@sub.domain.co.uk"
assert_failure "_validate_email rejects email missing domain" _validate_email "user@"
assert_failure "_validate_email rejects email missing @" _validate_email "user.domain.com"
assert_failure "_validate_email rejects empty email" _validate_email ""

# Test _ui_input and _ui_password
assert_eq "entered_val" "$(printf 'entered_val\n' | (NON_INTERACTIVE=false; _ui_input "Test prompt" "default"))" "_ui_input returns user input"
assert_eq "default_val" "$(printf '\n' | (NON_INTERACTIVE=false; _ui_input "Test prompt" "default_val"))" "_ui_input falls back to default on empty enter"
assert_eq "secret123" "$(printf 'secret123\n' | (NON_INTERACTIVE=false; _ui_password "Test password"))" "_ui_password returns hidden input"
assert_eq "headless_default" "$(_ui_input "Test prompt" "headless_default")" "_ui_input returns default in headless mode"
assert_eq "" "$(NON_INTERACTIVE=true _ui_bell 2>&1)" "_ui_bell suppressed in non-interactive mode"
assert_eq "" "$(DOTFILES_NO_BELL=true _ui_bell 2>&1)" "_ui_bell suppressed when DOTFILES_NO_BELL is true"
assert_eq "" "$(printf '%s' "$(date +%s)" > "${TMPDIR:-/tmp}/.dotfiles_bell_$$"; _ui_bell 2>&1)" "_ui_bell debounced on rapid consecutive calls"

# Test _select_config_file
(
    tmp_cfg_dir="$(mktemp -d)"
    CONFIG_FILE="init"
    _select_config_file "$tmp_cfg_dir"
    assert_eq "" "$CONFIG_FILE" "_select_config_file sets empty CONFIG_FILE when no user config exists"

    touch "$tmp_cfg_dir/work.conf"
    CONFIG_FILE=""
    _select_config_file "$tmp_cfg_dir"
    assert_eq "$tmp_cfg_dir/work.conf" "$CONFIG_FILE" "_select_config_file selects single custom config"

    touch "$tmp_cfg_dir/home.conf"
    chosen_cfg=""
    chosen_cfg="$(printf '2\n' | (CONFIG_FILE=""; NON_INTERACTIVE=false; _select_config_file "$tmp_cfg_dir"; printf '%s' "$CONFIG_FILE"))"
    assert_eq "$tmp_cfg_dir/work.conf" "$chosen_cfg" "_select_config_file selects choice interactively"
    rm -rf "$tmp_cfg_dir"
)

# Test _resolve_pkg
assert_eq "git" "$(_resolve_pkg "git" "" "apt")" "_resolve_pkg returns default when opts empty"
assert_eq "git-all" "$(_resolve_pkg "git" "apt:git-all dnf:git-core" "apt")" "_resolve_pkg returns apt override"
assert_eq "git-core" "$(_resolve_pkg "git" "apt:git-all dnf:git-core" "dnf")" "_resolve_pkg returns dnf override"
assert_eq "git" "$(_resolve_pkg "git" "apt:git-all dnf:git-core" "pacman")" "_resolve_pkg falls back to default when pm missing"

# Test _check_bins
assert_success "_check_bins returns 0 for existing binary 'bash'" _check_bins "bash"
assert_eq "bash" "$REPLY" "_check_bins sets REPLY to 'bash'"

assert_failure "_check_bins returns non-zero for missing binary" _check_bins "nonexistent_bin_12345"
assert_eq "" "$REPLY" "_check_bins sets REPLY to empty for missing binary"

assert_success "_check_bins returns 0 for comma-separated binary list with match" _check_bins "nonexistent_bin_12345, bash, sh"
assert_eq "bash" "$REPLY" "_check_bins sets REPLY to first existing binary"

# Test scope path classification
assert_success "_is_system_path returns 0 for /usr/bin/bash" _is_system_path "/usr/bin/bash"
assert_success "_is_system_path returns 0 for /usr/local/bin/rip" _is_system_path "/usr/local/bin/rip"
assert_failure "_is_system_path returns 1 for $HOME/.local/bin/node" _is_system_path "$HOME/.local/bin/node"
assert_success "_is_user_path returns 0 for $HOME/.local/bin/node" _is_user_path "$HOME/.local/bin/node"
assert_failure "_is_user_path returns 1 for /usr/bin/bash" _is_user_path "/usr/bin/bash"

# Test _check_bins_scoped
assert_success "_check_bins_scoped system bash succeeds" _check_bins_scoped "bash" "system"
assert_eq "bash" "$REPLY" "_check_bins_scoped sets REPLY to 'bash'"
assert_success "_check_bins_scoped returns system path" _is_system_path "$REPLY_PATH"

# Test user scoped binary with temporary binary in user dir
(
    tmp_user_bin="$HOME/.local/bin/test_scoped_user_bin_$$"
    mkdir -p "$HOME/.local/bin"
    touch "$tmp_user_bin" && chmod +x "$tmp_user_bin"
    bin_name="test_scoped_user_bin_$$"
    assert_success "_check_bins_scoped user matches $bin_name" _check_bins_scoped "$bin_name" "user"
    assert_failure "_check_bins_scoped system rejects $bin_name" _check_bins_scoped "$bin_name" "system"
    rm -f "$tmp_user_bin"

    # Test absolute non-executable file path (e.g. bash-completion)
    tmp_data_file="$TEST_TMP/mock_bash_completion_$$"
    touch "$tmp_data_file" && chmod 644 "$tmp_data_file"
    assert_success "_check_bins_scoped matches non-executable file path" _check_bins_scoped "$tmp_data_file" "system"
    assert_eq "$tmp_data_file" "$REPLY_PATH" "_check_bins_scoped sets correct REPLY_PATH for file path"
    rm -f "$tmp_data_file"
)

# Test _eval_cond: basic
if [[ "$(uname -s)" == "Linux" ]]; then
    assert_success "_eval_cond linux succeeds on Linux" _eval_cond 'linux' ''
    assert_failure "_eval_cond !linux fails on Linux" _eval_cond '!linux' ''
else
    assert_failure "_eval_cond linux fails on non-Linux" _eval_cond 'linux' ''
    assert_success "_eval_cond !linux succeeds on non-Linux" _eval_cond '!linux' ''
fi
assert_success "_eval_cond desktop succeeds when ENV=desktop" bash -c "source '${SETUP_SCRIPT}'; ENV='desktop'; _eval_cond 'desktop' ''"
assert_failure "_eval_cond desktop fails when ENV=vps" bash -c "source '${SETUP_SCRIPT}'; ENV='vps'; _eval_cond 'desktop' ''"
assert_success "_eval_cond env:desktop succeeds with normalized tag when ENV=desktop" bash -c "source '${SETUP_SCRIPT}'; ENV='desktop'; _eval_cond 'env:desktop' ''"

# Test _eval_cond: COND override path
reset_test_state
_CONF_CASCADE_DONE=1
COND="custom_flag"
assert_success "_eval_cond skips unknown cond when COND override matches" _eval_cond 'custom_flag' ''
assert_success "_eval_cond matches env prefix against bare COND override" bash -c "
  source '${SETUP_SCRIPT}'
  _CONF_CASCADE_DONE=1
  COND='vps'
  _eval_cond 'env:vps' ''
"
assert_failure "_eval_cond fails when DISABLE_COND suppresses matching cond" bash -c "
  source '${SETUP_SCRIPT}'
  _CONF_CASCADE_DONE=1
  DISABLE_COND='linux'
  _eval_cond 'linux' ''
"
unset COND

# Test _group_selected
reset_test_state
INSTALL_GROUPS=()
assert_success "_group_selected selects all groups when INSTALL_GROUPS empty" _group_selected "core"
INSTALL_GROUPS=("shell" "dev-tools")
assert_success "_group_selected selects group in filter list" _group_selected "shell"
assert_failure "_group_selected rejects group not in filter list" _group_selected "core"
INSTALL_GROUPS=()

# Test reset_test_state
reset_test_state
_CONF_PKG_KEYS["test:key"]="value"
DRY_RUN=true
reset_test_state
assert_eq "" "${_CONF_PKG_KEYS["test:key"]:-}" "reset_test_state clears _CONF_PKG_KEYS"
assert_eq "false" "$DRY_RUN" "reset_test_state resets DRY_RUN flag"

# Test user-scope provider opt extraction
assert_eq "ruff" "$(_get_opt uv 'uv:"ruff" cargo:"ripgrep"')" "_get_opt extracts uv provider"
assert_eq "ripgrep" "$(_get_opt cargo 'uv:"ruff" cargo:"ripgrep"')" "_get_opt extracts cargo provider"
assert_eq "golang.org/x/tools/gopls" "$(_get_opt go 'go:"golang.org/x/tools/gopls"')" "_get_opt extracts go provider"
assert_eq "prettier" "$(_get_opt bun 'bun:"prettier"')" "_get_opt extracts bun provider"
assert_eq "eslint" "$(_get_opt npm 'npm:"eslint"')" "_get_opt extracts npm provider"
assert_eq "com.obsproject.Studio" "$(_get_opt flatpak 'flatpak:"com.obsproject.Studio"')" "_get_opt extracts flatpak provider"
assert_eq "gcc" "$(_get_opt brew 'brew:"gcc"')" "_get_opt extracts brew provider"

# Test case-insensitivity in config parsing
reset_test_state
case_cfg="${TEST_TMP}/case_test.conf"
cat << 'EOF' > "$case_cfg"
[config]
GROUPS = core, shell
Packages = bat,
    ripgrep,
    zstd
EXCLUDE = docker
Cond = wsl
EOF

_parse_single_conf_file "$case_cfg" "global"
assert_eq "core, shell" "${_CONF_PKG_KEYS["global:groups"]:-}" "Case-insensitive GROUPS normalizes to global:groups"
assert_eq "bat, ripgrep, zstd" "${_CONF_PKG_KEYS["global:packages"]:-}" "Multiline Packages accumulates correctly"
assert_eq "docker" "${_CONF_PKG_KEYS["global:exclude"]:-}" "Case-insensitive EXCLUDE normalizes to global:exclude"
assert_eq "wsl" "${_CONF_PKG_KEYS["global:cond"]:-}" "Case-insensitive Cond normalizes to global:cond"

echo "  Section Results: ${PASSED_COUNT} passed, ${FAILED_COUNT} failed."
[[ $FAILED_COUNT -eq 0 ]] || exit 1
