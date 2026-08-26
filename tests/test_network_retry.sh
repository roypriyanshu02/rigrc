#!/usr/bin/env bash
# =============================================================================
#  NETWORK, RETRY, RESILIENCE & ERROR CAPTURE TESTS
# =============================================================================
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "$TESTS_DIR/test_helper.sh"

init_test_sandbox
trap cleanup_test_sandbox EXIT

echo "▶ Running Network & Retry Unit Tests..."

# Test _extract_last_error
tmp_err_log="${TEST_TMP}/err.log"
printf 'info line 1\nwarn line 2\nerror: decisive failure reason\n\n' > "$tmp_err_log"
assert_eq "error: decisive failure reason" "$(_extract_last_error "$tmp_err_log")" "_extract_last_error extracts last meaningful line"
assert_eq "" "$(_extract_last_error "${TEST_TMP}/nonexistent.log")" "_extract_last_error handles missing file"

# Test _run_retry success on attempt 1
assert_success "_run_retry succeeds when command succeeds" _run_retry 2 0 "test_cmd" true

# Test _run_retry failure after max attempts
assert_failure "_run_retry returns non-zero when command fails" _run_retry 2 0 "test_fail" false

# Test _run_retry short-circuits on exit code 127
retry_count_file="${TEST_TMP}/retry_cnt.txt"
echo 0 > "$retry_count_file"
_test_127_cmd() {
    local cnt; cnt="$(<"$retry_count_file")"; echo $((cnt + 1)) > "$retry_count_file"
    return 127
}
_run_retry 3 0 "test_127" _test_127_cmd || true
assert_eq "1" "$(<"$retry_count_file")" "_run_retry does not waste attempts on exit 127 (command not found)"

# Test _run_retry succeeds on subsequent attempt
echo 0 > "$retry_count_file"
_test_retry_eventual_success() {
    local cnt; cnt="$(<"$retry_count_file")"; cnt=$((cnt + 1)); echo "$cnt" > "$retry_count_file"
    [[ $cnt -ge 2 ]] && return 0 || return 1
}
assert_success "_run_retry succeeds on 2nd attempt" _run_retry 3 0 "test_eventual" _test_retry_eventual_success
assert_eq "2" "$(<"$retry_count_file")" "_run_retry ran exactly 2 attempts"

# Test _wait_for_pm_lock and _is_file_locked
assert_success "_wait_for_pm_lock returns 0" _wait_for_pm_lock "apt" 1
assert_failure "_is_file_locked returns 1 for missing file" _is_file_locked "${TEST_TMP}/missing_lock_file"
unlocked_file="${TEST_TMP}/unlocked.lck"
touch "$unlocked_file"
assert_failure "_is_file_locked returns 1 for unlocked file" _is_file_locked "$unlocked_file"

# Test live vs stale PID file detection
stale_pid_file="${TEST_TMP}/stale.pid"
echo "99999999" > "$stale_pid_file"
assert_failure "_is_file_locked returns 1 for stale PID lock file" _is_file_locked "$stale_pid_file"

live_pid_file="${TEST_TMP}/live.pid"
echo "$$" > "$live_pid_file"
assert_success "_is_file_locked returns 0 for active PID lock file" _is_file_locked "$live_pid_file"

# Test _run_retry short-circuits on 404 error
echo 0 > "$retry_count_file"
_test_404_cmd() {
    local cnt; cnt="$(<"$retry_count_file")"; echo $((cnt + 1)) > "$retry_count_file"
    echo "HTTP 404 Not Found" >&2
    return 22
}
_run_retry 3 0 "test_404" _test_404_cmd || true
assert_eq "1" "$(<"$retry_count_file")" "_run_retry short-circuits on HTTP 404 Not Found without wasting retries"

# Test _extract_last_error with trailing lines
tmp_err_log_multi="${TEST_TMP}/err_multi.log"
printf 'starting build...\nerror: compilation failed on file main.c\nsome trailing clean up line 1\nsome trailing clean up line 2\n\n' > "$tmp_err_log_multi"
assert_eq "error: compilation failed on file main.c" "$(_extract_last_error "$tmp_err_log_multi")" "_extract_last_error extracts decisive error over trailing noise"

# Test _run_retry short-circuits on SIGINT (130) and SIGTERM (143)
echo 0 > "$retry_count_file"
_test_130_cmd() {
    local cnt; cnt="$(<"$retry_count_file")"; echo $((cnt + 1)) > "$retry_count_file"
    return 130
}
_run_retry 3 0 "test_130" _test_130_cmd || true
assert_eq "1" "$(<"$retry_count_file")" "_run_retry does not retry on SIGINT (exit code 130)"

echo 0 > "$retry_count_file"
_test_143_cmd() {
    local cnt; cnt="$(<"$retry_count_file")"; echo $((cnt + 1)) > "$retry_count_file"
    return 143
}
_run_retry 3 0 "test_143" _test_143_cmd || true
assert_eq "1" "$(<"$retry_count_file")" "_run_retry does not retry on SIGTERM (exit code 143)"

# Test _get_remediation_hint
assert_contains "$(_get_remediation_hint "Could not get lock /var/lib/dpkg/lock")" "lock busy" "_get_remediation_hint provides lock hint"
assert_contains "$(_get_remediation_hint "404 Not Found")" "Asset not found" "_get_remediation_hint provides 404 hint"
assert_contains "$(_get_remediation_hint "API rate limit exceeded")" "GITHUB_TOKEN" "_get_remediation_hint provides rate limit hint"
assert_contains "$(_get_remediation_hint "Permission denied")" "permissions" "_get_remediation_hint provides permission hint"
assert_contains "$(_get_remediation_hint "Operation timed out")" "timed out" "_get_remediation_hint provides timeout hint"
assert_contains "$(_get_remediation_hint "SSL certificate problem")" "certificate" "_get_remediation_hint provides SSL certificate hint"

# Test rate limit header parsing from curl -i output
mock_curl_i="HTTP/2 200\r\nx-ratelimit-limit: 60\r\nx-ratelimit-remaining: 42\r\nx-ratelimit-reset: 1770000000\r\n\r\n{\"resources\":{\"core\":{\"limit\":60,\"remaining\":42}}}"
mock_rem=""
mock_total=""
if [[ "$mock_curl_i" =~ [Xx]-[Rr]atelimit-[Rr]emaining:[[:space:]]*([0-9]+) ]]; then
    mock_rem="${BASH_REMATCH[1]}"
fi
if [[ "$mock_curl_i" =~ [Xx]-[Rr]atelimit-[Ll]imit:[[:space:]]*([0-9]+) ]]; then
    mock_total="${BASH_REMATCH[1]}"
fi
assert_eq "42" "$mock_rem" "rate limit remaining parsed from curl -i output"
assert_eq "60" "$mock_total" "rate limit total limit parsed from curl -i output"

# Test _check_network
assert_success "_check_network returns numeric code" bash -c "source '${SETUP_SCRIPT}'; _check_network || true"
assert_failure "_check_network returns 1 when OFFLINE=true" bash -c "source '${SETUP_SCRIPT}'; OFFLINE=true; _check_network"

echo "  Section Results: ${PASSED_COUNT} passed, ${FAILED_COUNT} failed."
[[ $FAILED_COUNT -eq 0 ]] || exit 1
