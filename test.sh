#!/usr/bin/env bash
# =============================================================================
#  MASTER AUTOMATED TEST RUNNER: Modular Test Suite Orchestrator
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"
SETUP_SCRIPT="${SETUP_SCRIPT:-$SCRIPT_DIR/rigrc.sh}"

# Ensure rigrc.sh bundle exists before running tests
if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "rigrc.sh not found. Building standalone bundle..."
    "$SCRIPT_DIR/build.sh"
fi

SUITES=(
    "test_cli.sh"
    "test_parser.sh"
    "test_network_retry.sh"
    "test_installer_deploy.sh"
)

# Optional filter argument (e.g. ./test.sh cli or ./test.sh parser)
FILTER="${1:-all}"
if [[ "$FILTER" != "all" && "$FILTER" != "--all" ]]; then
    MATCHED=()
    for s in "${SUITES[@]}"; do
        if [[ "$s" == *"$FILTER"* ]]; then
            MATCHED+=("$s")
        fi
    done
    if [[ ${#MATCHED[@]} -eq 0 ]]; then
        echo "Error: No test suite matched filter '$FILTER'." >&2
        echo "Available suites:" >&2
        for s in "${SUITES[@]}"; do
            echo "  - ${s%.sh}" >&2
        done
        exit 1
    fi
    SUITES=("${MATCHED[@]}")
fi

echo "========================================================"
echo " Starting Dotfiles Automated Test Suite (${#SUITES[@]} modules)"
echo "========================================================"

TOTAL_START=$SECONDS
OVERALL_STATUS=0

for suite in "${SUITES[@]}"; do
    suite_path="$TESTS_DIR/$suite"
    if [[ ! -f "$suite_path" ]]; then
        echo "Error: Test suite file not found: $suite_path" >&2
        OVERALL_STATUS=1
        continue
    fi
    chmod +x "$suite_path" 2>/dev/null || true
    echo ""
    if ! "$suite_path"; then
        OVERALL_STATUS=1
        echo "✗ Test suite failed: $suite" >&2
    fi
done

TOTAL_ELAPSED=$(( SECONDS - TOTAL_START ))

echo ""
echo "========================================================"
if [[ $OVERALL_STATUS -eq 0 ]]; then
    echo " ALL TEST SUITES PASSED cleanly in ${TOTAL_ELAPSED}s."
    echo "========================================================"
    exit 0
else
    echo " TEST SUITE RUN COMPLETED WITH FAILURES in ${TOTAL_ELAPSED}s."
    echo "========================================================"
    exit 1
fi
