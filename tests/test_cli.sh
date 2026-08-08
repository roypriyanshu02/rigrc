#!/usr/bin/env bash
# =============================================================================
#  CLI SMOKE & ARGUMENT PARSING TESTS
# =============================================================================
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "$TESTS_DIR/test_helper.sh"

init_test_sandbox
trap cleanup_test_sandbox EXIT

echo "▶ Running CLI Smoke Tests..."

assert_success "CLI --help returns 0" "${SETUP_SCRIPT}" --help
assert_success "CLI --lint returns 0" "${SETUP_SCRIPT}" --lint
assert_success "CLI --doctor returns 0" "${SETUP_SCRIPT}" --doctor
assert_success "CLI --doctor --fix returns 0" "${SETUP_SCRIPT}" --doctor --fix
assert_success "CLI --clean-symlinks returns 0" "${SETUP_SCRIPT}" --clean-symlinks
assert_failure "CLI rejected --dry-run flag exits non-zero" "${SETUP_SCRIPT}" --dry-run
assert_success "CLI --fmt --check-only returns 0" "${SETUP_SCRIPT}" --fmt --check-only
assert_failure "CLI invalid flag exits non-zero" "${SETUP_SCRIPT}" --invalid-flag-xyz
assert_failure "CLI rejected --test flag exits non-zero" "${SETUP_SCRIPT}" --test
assert_success "packages/_groups.conf has [group:core] section" grep -q '\[group:core\]' "${GROUPS_CONF}"

echo "  Section Results: ${PASSED_COUNT} passed, ${FAILED_COUNT} failed."
[[ $FAILED_COUNT -eq 0 ]] || exit 1
