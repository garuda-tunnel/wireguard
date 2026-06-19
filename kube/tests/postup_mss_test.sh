#!/usr/bin/env bash
# Unit test for postup.sh MSS clamp — Task 2 env var contract.
#
# Stubs out `nft` so we can capture the generated ruleset without a live
# kernel, then asserts:
#   1. oifname clamp-to-pmtu line is present (unconditional, must NOT regress).
#   2. iifname fixed-MSS line is present when WG_MSS_CLAMP_ENABLED=true.
#   3. No ICMP drop/reject is introduced (AC8 negative).
#   4. Forward chain policy is accept (AC8 positive — ICMP PTB transits).
#   5. WG_MSS_CLAMP_ENABLED=false: iifname rule absent, oifname present.
#   6. WG_MSS_CLAMP_ENABLED unset: iifname rule absent (default-off guard).
#
# Usage: bash kube/tests/postup_mss_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_FAIL=0

# ---------------------------------------------------------------------------
# Helper: run one test case.
#
# Arguments:
#   $1 — test case label
#   $2 — WG_FIXED_MSS value to export
#   $3 — WG_MSS_CLAMP_ENABLED value to export (set to "" to leave unset)
#   $4 — assertion callback function name
# ---------------------------------------------------------------------------
run_case() {
    local label="$1"
    local wg_fixed_mss="$2"
    local wg_mss_clamp_enabled="$3"
    local assert_fn="$4"

    local TMP
    TMP=$(mktemp -d)
    local CAPTURE="$TMP/ruleset"
    local LOG="$TMP/stdout"
    touch "$CAPTURE"

    # Stub nft: when called with -f -, consume stdin into CAPTURE.
    # Any other invocation (add table, delete table) is a no-op.
    cat > "$TMP/nft" <<'NFTSTUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-f" ]; then
    cat >> "$CAPTURE"
fi
exit 0
NFTSTUB
    chmod +x "$TMP/nft"

    local saved_path="$PATH"
    export PATH="$TMP:$PATH"
    export CAPTURE

    export WG_INTERFACE="wg-test"
    export WG_NIC_ATTACH='[]'
    export WG_FIXED_MSS="$wg_fixed_mss"

    if [ -n "$wg_mss_clamp_enabled" ]; then
        export WG_MSS_CLAMP_ENABLED="$wg_mss_clamp_enabled"
    else
        unset WG_MSS_CLAMP_ENABLED
    fi

    bash "${SCRIPT_DIR}/../image/postup.sh" > "$LOG" 2>&1 || true

    echo "=== Test case: ${label} ==="
    echo "--- captured ruleset ---"
    cat "$CAPTURE"
    echo "--- postup log ---"
    cat "$LOG"
    echo "--- end ---"

    local case_fail=0
    "$assert_fn" "$CAPTURE" "$LOG" case_fail

    rm -rf "$TMP"
    export PATH="$saved_path"

    return "$case_fail"
}

# ---------------------------------------------------------------------------
# Assertion: clamp enabled (WG_FIXED_MSS=1290, WG_MSS_CLAMP_ENABLED=true)
# ---------------------------------------------------------------------------
assert_clamp_enabled() {
    local capture="$1"
    local log="$2"
    local -n _fail=$3

    # 1. oifname clamp-to-pmtu unconditional.
    if grep -q "oifname \"wg-test\" tcp flags syn tcp option maxseg size set rt mtu" "$capture"; then
        echo "PASS: oifname clamp-to-pmtu present"
    else
        echo "FAIL: oifname clamp-to-pmtu MISSING"
        _fail=1
    fi

    # 2. iifname fixed-MSS clamp when enabled.
    if grep -q "iifname \"wg-test\" tcp flags syn tcp option maxseg size set 1290" "$capture"; then
        echo "PASS: iifname fixed-MSS 1290 present"
    else
        echo "FAIL: iifname fixed-MSS MISSING (expected 'iifname \"wg-test\" ... set 1290')"
        _fail=1
    fi

    # 3. AC8 negative — no ICMP drop/reject.
    if grep -qiE 'icmp.*(drop|reject)|(drop|reject).*icmp' "$capture"; then
        echo "FAIL: ICMP drop/reject found (AC8 violated)"
        _fail=1
    else
        echo "PASS: no ICMP drop/reject"
    fi

    # 4. AC8 positive — forward chain policy is accept.
    if grep -q "policy accept" "$capture"; then
        echo "PASS: policy accept present"
    else
        echo "FAIL: policy accept MISSING"
        _fail=1
    fi

    # 5. Legacy WG_MTU must NOT appear in log/ruleset.
    if grep -q "WG_MTU" "$log" "$capture" 2>/dev/null; then
        echo "FAIL: legacy WG_MTU reference found (must be replaced by WG_FIXED_MSS)"
        _fail=1
    else
        echo "PASS: no legacy WG_MTU references"
    fi
}

# ---------------------------------------------------------------------------
# Assertion: clamp disabled (WG_MSS_CLAMP_ENABLED=false).
#   - iifname rule must be ABSENT.
#   - oifname rt-mtu rule must still be PRESENT.
# ---------------------------------------------------------------------------
assert_clamp_disabled() {
    local capture="$1"
    local log="$2"
    local -n _fail=$3

    # oifname still present.
    if grep -q "oifname \"wg-test\" tcp flags syn tcp option maxseg size set rt mtu" "$capture"; then
        echo "PASS: oifname clamp-to-pmtu present when clamp disabled"
    else
        echo "FAIL: oifname clamp-to-pmtu MISSING when clamp disabled"
        _fail=1
    fi

    # iifname rule must be absent.
    if grep -q "iifname" "$capture"; then
        echo "FAIL: iifname rule present when WG_MSS_CLAMP_ENABLED=false (should be omitted)"
        _fail=1
    else
        echo "PASS: iifname rule correctly absent when clamp disabled"
    fi

    # Log must mention clamp not enabled.
    if grep -q "WG_MSS_CLAMP_ENABLED not true" "$log"; then
        echo "PASS: log reports clamp not enabled"
    else
        echo "FAIL: log does not report clamp not enabled"
        _fail=1
    fi
}

# ---------------------------------------------------------------------------
# Assertion: WG_MSS_CLAMP_ENABLED unset (default-off guard).
#   Same expectations as disabled: iifname absent, oifname present.
# ---------------------------------------------------------------------------
assert_clamp_unset() {
    local capture="$1"
    local log="$2"
    local -n _fail=$3

    if grep -q "oifname \"wg-test\" tcp flags syn tcp option maxseg size set rt mtu" "$capture"; then
        echo "PASS: oifname clamp-to-pmtu present when clamp unset"
    else
        echo "FAIL: oifname clamp-to-pmtu MISSING when clamp unset"
        _fail=1
    fi

    if grep -q "iifname" "$capture"; then
        echo "FAIL: iifname rule present when WG_MSS_CLAMP_ENABLED unset (should be omitted)"
        _fail=1
    else
        echo "PASS: iifname rule correctly absent when clamp unset"
    fi
}

# ---------------------------------------------------------------------------
# Run test cases
# ---------------------------------------------------------------------------
FAIL_ENABLED=0
FAIL_DISABLED=0
FAIL_UNSET=0

run_case "clamp enabled (WG_FIXED_MSS=1290, WG_MSS_CLAMP_ENABLED=true)" \
    "1290" "true" assert_clamp_enabled || FAIL_ENABLED=$?
echo ""

run_case "clamp disabled (WG_FIXED_MSS=1290, WG_MSS_CLAMP_ENABLED=false)" \
    "1290" "false" assert_clamp_disabled || FAIL_DISABLED=$?
echo ""

run_case "clamp unset (WG_MSS_CLAMP_ENABLED not exported)" \
    "1290" "" assert_clamp_unset || FAIL_UNSET=$?

echo ""
echo "=== Summary ==="
[ "$FAIL_ENABLED"  -eq 0 ] && echo "PASS: clamp enabled"  || echo "FAIL: clamp enabled"
[ "$FAIL_DISABLED" -eq 0 ] && echo "PASS: clamp disabled" || echo "FAIL: clamp disabled"
[ "$FAIL_UNSET"    -eq 0 ] && echo "PASS: clamp unset"    || echo "FAIL: clamp unset"

TOTAL_FAIL=$(( FAIL_ENABLED + FAIL_DISABLED + FAIL_UNSET ))

if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "postup MSS test PASS"
    exit 0
else
    echo "postup MSS test FAIL"
    exit 1
fi
