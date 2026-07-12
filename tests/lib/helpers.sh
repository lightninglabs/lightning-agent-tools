#!/usr/bin/env bash
# Test helper functions: assertions, progress tracking, summary.
#
# Usage:
#   source tests/lib/helpers.sh
#
# Provides:
#   REPO_ROOT           - absolute path to the repository root
#   begin_test NAME     - start a test case
#   end_test            - finish the current test case
#   assert_eq A B MSG   - fail if A != B
#   assert_neq A B MSG  - fail if A == B
#   assert_contains HAYSTACK NEEDLE MSG - fail if NEEDLE not in HAYSTACK
#   print_header LABEL  - print a section header
#   print_summary       - print pass/fail totals; exit non-zero on failures

HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HELPERS_DIR/../.." && pwd)"

# Counters.
_TESTS_RUN=0
_TESTS_PASSED=0
_TESTS_FAILED=0
_CURRENT_TEST=""

# Color codes (disabled when stdout is not a terminal).
if [ -t 1 ]; then
    _GREEN='\033[0;32m'
    _RED='\033[0;31m'
    _YELLOW='\033[0;33m'
    _BOLD='\033[1m'
    _RESET='\033[0m'
else
    _GREEN=''
    _RED=''
    _YELLOW=''
    _BOLD=''
    _RESET=''
fi

# begin_test starts a test case. Must be followed by end_test.
begin_test() {
    _CURRENT_TEST="$1"
    _CURRENT_FAILED=false
    (( _TESTS_RUN++ )) || true
}

# end_test finishes the current test case and prints the result.
end_test() {
    if [ "$_CURRENT_FAILED" = true ]; then
        printf "  ${_RED}FAIL${_RESET} %s\n" "$_CURRENT_TEST"
    else
        (( _TESTS_PASSED++ )) || true
        printf "  ${_GREEN}PASS${_RESET} %s\n" "$_CURRENT_TEST"
    fi
    _CURRENT_TEST=""
}

# _fail records a failure for the current test.
_fail() {
    local msg="$1"
    _CURRENT_FAILED=true
    (( _TESTS_FAILED++ )) || true
    printf "       ${_RED}=> %s${_RESET}\n" "$msg" >&2
}

# assert_eq fails if the two values are not equal.
assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-expected '$expected', got '$actual'}"
    if [ "$actual" != "$expected" ]; then
        _fail "$msg (expected '$expected', got '$actual')"
    fi
}

# assert_neq fails if the two values are equal.
assert_neq() {
    local actual="$1"
    local unexpected="$2"
    local msg="${3:-expected value other than '$unexpected'}"
    if [ "$actual" = "$unexpected" ]; then
        _fail "$msg (got '$actual')"
    fi
}

# assert_contains fails if the haystack does not contain the needle
# (case-insensitive grep).
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-output should contain '$needle'}"
    if ! echo "$haystack" | grep -qi "$needle"; then
        _fail "$msg"
    fi
}

# print_header prints a section divider.
print_header() {
    local label="$1"
    printf "\n${_BOLD}── %s ──${_RESET}\n" "$label"
}

# print_summary prints the final tally and exits non-zero on failures.
print_summary() {
    echo ""
    printf "${_BOLD}Results:${_RESET} "
    printf "%d tests, " "$_TESTS_RUN"
    printf "${_GREEN}%d passed${_RESET}, " "$_TESTS_PASSED"
    printf "${_RED}%d failed${_RESET}\n" "$_TESTS_FAILED"

    if [ "$_TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}
