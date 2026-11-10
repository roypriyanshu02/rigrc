#!/usr/bin/env bash
# =============================================================================
#  TEST HELPER: Shared Utilities, Assertions, and Sandbox Lifecycle
# =============================================================================
# shellcheck shell=bash

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SETUP_SCRIPT="${SETUP_SCRIPT:-$REPO_ROOT/rigrc.sh}"

# Test tracking counters
PASSED_COUNT=0
FAILED_COUNT=0

# Ensure rigrc.sh bundle exists
if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "rigrc.sh not found. Compiling standalone bundle..."
    "$REPO_ROOT/build.sh"
fi

# Source bundle functions for in-process testing
# shellcheck source=/dev/null
source "$SETUP_SCRIPT"

# ---------------------------------------------------------------------------
# Test Assertions
# ---------------------------------------------------------------------------
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ✓ %s\n' "$msg"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo "  ✗ FAIL: ${msg} (expected '${expected}', got '${actual}')" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ✓ %s\n' "$msg"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo "  ✗ FAIL: ${msg} (expected to contain '${needle}')" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

assert_success() {
    local msg="$1"
    shift
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then
        printf '  ✓ %s\n' "$msg"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo "  ✗ FAIL: ${msg} (command exited with status ${rc}: $*)" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

assert_failure() {
    local msg="$1"
    shift
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        printf '  ✓ %s\n' "$msg"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo "  ✗ FAIL: ${msg} (expected failure but command succeeded: $*)" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

# ---------------------------------------------------------------------------
# Sandbox Setup & State Resetter
# ---------------------------------------------------------------------------
init_test_sandbox() {
    TEST_TMP="$(mktemp -d)"
    export TEST_TMP
    export DOTFILES_DIR="${TEST_TMP}/dotfiles"
    export HOME="${TEST_TMP}/home"
    export XDG_BIN_HOME="${HOME}/.local/bin"
    export XDG_DATA_HOME="${HOME}/.local/share"
    export XDG_CONFIG_HOME="${HOME}/.config"
    export XDG_CACHE_HOME="${HOME}/.cache"
    export XDG_STATE_HOME="${HOME}/.local/state"
    export NON_INTERACTIVE=true
    mkdir -p "$DOTFILES_DIR" "$HOME"
}

cleanup_test_sandbox() {
    if [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

reset_test_state() {
    _CONF_PARSED=()
    _CONF_PKG_NAME=()
    _CONF_PKG_BIN=()
    _CONF_PKG_DESC=()
    _CONF_PKG_SCOPE=()
    _CONF_PKG_INSTALL=()
    _CONF_PKG_OPTS=()
    _CONF_BASHRC=()
    _CONF_TEMPLATES=()
    _CONF_PKG_KEYS=()
    _CONF_PKG_DISABLED=()
    _CONF_PKG_DECLINED=()
    _CONF_BASHRC_BUF=()
    _CONF_BASHRC_DIS=()
    _CONF_TMPL_BUF=()
    _CONF_TMPL_DIS=()
    _CONF_CASCADE_DONE=0
    _WARNING_MESSAGES=()
    _DEP_RESOLVE_STACK=()
    _INSTALLED_PACKAGES_COUNT=0
    _SYS_ARCH_CACHE=""
    _SYS_DISTRO_CACHE=""
    _SYS_ENV_CACHE=""
    _SYS_IS_WSL_CACHE=""
    _SYS_IS_CONTAINER_CACHE=""
    _SYS_OS_CACHE=""
    DRY_RUN=false
    VERBOSE=false
    FORCE=false
    INSTALL_GROUPS=()
    OPTIONAL_PACKAGES=()
    BACKUP_COUNT=0
    BACKUP_DIR=""
}
