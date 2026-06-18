#!/usr/bin/env bash
# Unit test for postup.sh MSS clamp — bidirectional (Task 1).
#
# Stubs out `nft` so we can capture the generated ruleset without a live
# kernel, then asserts:
#   1. oifname clamp-to-pmtu line is present (existing, must NOT regress).
#   2. iifname fixed-MSS line is present (new, Task 1 addition).
#   3. No ICMP drop/reject is introduced (AC8 negative).
#   4. Forward chain policy is accept (AC8 positive — ICMP PTB transits).
#   5. WG_MSS=0 (sysfs unavailable): iifname rule absent, oifname present, log correct.
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
#   $2 — WG_MTU value to export (set to "" to leave unset, simulating sysfs miss)
#   $3 — assertion callback function name
# ---------------------------------------------------------------------------
run_case() {
    local label="$1"
    local wg_mtu="$2"
    local assert_fn="$3"

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

    if [ -n "$wg_mtu" ]; then
        export WG_MTU="$wg_mtu"
    else
        unset WG_MTU
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
# Assertion: normal case (WG_MTU=1330, WG_MSS=1290)
# ---------------------------------------------------------------------------
assert_normal() {
    local capture="$1"
    local log="$2"
    local -n _fail=$3

    # 1. oifname clamp-to-pmtu.
    if grep -q "oifname \"wg-test\" tcp flags syn tcp option maxseg size set rt mtu" "$capture"; then
        echo "PASS: oifname clamp-to-pmtu present"
    else
        echo "FAIL: oifname clamp-to-pmtu MISSING"
        _fail=1
    fi

    # 2. iifname fixed-MSS clamp.
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
}

# ---------------------------------------------------------------------------
# Assertion: WG_MSS=0 / sysfs unavailable (WG_MTU not set, sysfs returns 0).
#   - iifname rule must be ABSENT (no "iifname 0" noise).
#   - oifname rt-mtu rule must still be PRESENT.
#   - Log must NOT contain "iifname 0".
#   - Log must contain "WG_MTU unavailable".
# ---------------------------------------------------------------------------
assert_mss_zero() {
    local capture="$1"
    local log="$2"
    local -n _fail=$3

    # oifname still present.
    if grep -q "oifname \"wg-test\" tcp flags syn tcp option maxseg size set rt mtu" "$capture"; then
        echo "PASS: oifname clamp-to-pmtu present when MSS=0"
    else
        echo "FAIL: oifname clamp-to-pmtu MISSING when MSS=0"
        _fail=1
    fi

    # iifname rule must be absent.
    if grep -q "iifname" "$capture"; then
        echo "FAIL: iifname rule present when WG_MSS=0 (should be omitted)"
        _fail=1
    else
        echo "PASS: iifname rule correctly absent when WG_MSS=0"
    fi

    # Log must not contain misleading "iifname 0".
    if grep -q "iifname 0" "$log"; then
        echo "FAIL: misleading 'iifname 0' found in log"
        _fail=1
    else
        echo "PASS: no misleading 'iifname 0' in log"
    fi

    # Log must mention WG_MTU unavailable.
    if grep -q "WG_MTU unavailable" "$log"; then
        echo "PASS: log reports WG_MTU unavailable"
    else
        echo "FAIL: log does not report WG_MTU unavailable"
        _fail=1
    fi
}

# ---------------------------------------------------------------------------
# Run test cases
# ---------------------------------------------------------------------------
FAIL_NORMAL=0
FAIL_MSS_ZERO=0

run_case "normal WG_MTU=1330" "1330" assert_normal || FAIL_NORMAL=$?
echo ""
# Simulate sysfs unavailable: WG_MTU unset and sysfs returns 0 (stub sysfs via WG_MTU=0).
run_case "WG_MSS=0 (sysfs fail / WG_MTU=0)" "0" assert_mss_zero || FAIL_MSS_ZERO=$?

echo ""
echo "=== Summary ==="
[ "$FAIL_NORMAL"   -eq 0 ] && echo "PASS: normal case"    || echo "FAIL: normal case"
[ "$FAIL_MSS_ZERO" -eq 0 ] && echo "PASS: WG_MSS=0 case"  || echo "FAIL: WG_MSS=0 case"

TOTAL_FAIL=$(( FAIL_NORMAL + FAIL_MSS_ZERO ))

if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "postup MSS bidirectional test PASS"
    exit 0
else
    echo "postup MSS bidirectional test FAIL"
    exit 1
fi
