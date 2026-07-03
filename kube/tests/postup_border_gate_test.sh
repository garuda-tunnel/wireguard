#!/usr/bin/env bash
# Verifies postup.sh Block-2 gates on `ip link show border` (interface
# presence), NOT on the removed WG_NIC_ATTACH env. Stubs nft (no-op) and
# ip: `link show border` returns success/failure per case, and `-4 route
# list dev <backbone|border> scope link` returns realistic single-line
# CIDR output (RFC5737 TEST-NET ranges) so the RPDB gateway computation in
# Blocks 3-4 actually succeeds instead of operating on empty input.
#
# The border-present case does NOT swallow postup.sh's exit code: it
# requires exit 0 and asserts the NAT log line plus BOTH RPDB completion
# log lines (via_tunnel and border_egress), so a failure anywhere in the
# RPDB setup (Blocks 3-4) fails the test instead of passing silently.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0

# Sets up nft/ip stubs in a fresh tmp dir and prints its path.
#   $1 — exit code `ip link show border` should return (0=present, 1=absent)
setup_stubs() {
  local border_present="$1"
  local TMP; TMP=$(mktemp -d)
  cat > "$TMP/nft" <<'NFT'
#!/usr/bin/env bash
[ "${1:-}" = "-f" ] && cat >/dev/null
exit 0
NFT
  cat > "$TMP/ip" <<IPSTUB
#!/usr/bin/env bash
if [ "\$1" = "link" ] && [ "\$2" = "show" ] && [ "\$3" = "border" ]; then
  exit ${border_present}
fi
if [ "\$1" = "-4" ] && [ "\$2" = "route" ] && [ "\$3" = "list" ] && [ "\$4" = "dev" ] && [ "\$5" = "backbone" ] && [ "\$6" = "scope" ] && [ "\$7" = "link" ]; then
  echo "192.0.2.0/24 scope link"
  exit 0
fi
if [ "\$1" = "-4" ] && [ "\$2" = "route" ] && [ "\$3" = "list" ] && [ "\$4" = "dev" ] && [ "\$5" = "border" ] && [ "\$6" = "scope" ] && [ "\$7" = "link" ]; then
  echo "198.51.100.0/24 scope link"
  exit 0
fi
exit 0
IPSTUB
  chmod +x "$TMP/nft" "$TMP/ip"
  echo "$TMP"
}

# --- Case: border present -> NAT applied AND RPDB setup completes, exit 0 ---
TMP="$(setup_stubs 0)"
saved_path="$PATH"; export PATH="$TMP:$PATH"
export WG_INTERFACE="wg-test" WG_FIXED_MSS="1290" WG_MSS_CLAMP_ENABLED="true"
LOG="$TMP/log"
set +e
bash "${SCRIPT_DIR}/../image/postup.sh" > "$LOG" 2>&1
RC=$?
set -e
export PATH="$saved_path"
if [ "$RC" -ne 0 ]; then
  echo "FAIL: border present must exit 0, got ${RC}"; cat "$LOG"; FAIL=1
else
  case_ok=1
  for expect in \
    "border masquerade applied" \
    "[POSTUP] RPDB via_tunnel configured: iif backbone -> dev wg-test" \
    "[POSTUP] RPDB border_egress configured: iif wg-test -> dev border"
  do
    if ! grep -qF "$expect" "$LOG"; then
      echo "FAIL: border present (expected log to contain '${expect}')"; cat "$LOG"
      case_ok=0; FAIL=1
    fi
  done
  [ "$case_ok" -eq 1 ] && echo "PASS: border present installs NAT and completes RPDB setup"
fi
rm -rf "$TMP"

# --- Case: border absent -> legitimate clean exit 0, NAT/RPDB skipped ---
TMP="$(setup_stubs 1)"
saved_path="$PATH"; export PATH="$TMP:$PATH"
export WG_INTERFACE="wg-test" WG_FIXED_MSS="1290" WG_MSS_CLAMP_ENABLED="true"
LOG="$TMP/log"
set +e
bash "${SCRIPT_DIR}/../image/postup.sh" > "$LOG" 2>&1
RC=$?
set -e
export PATH="$saved_path"
if [ "$RC" -ne 0 ]; then
  echo "FAIL: border absent must exit 0, got ${RC}"; cat "$LOG"; FAIL=1
elif grep -qF "border interface not present" "$LOG"; then
  echo "PASS: border absent skips NAT"
else
  echo "FAIL: border absent (expected log to contain 'border interface not present')"; cat "$LOG"; FAIL=1
fi
rm -rf "$TMP"

if [ "$FAIL" -eq 0 ]; then
  echo "postup border gate PASS"
  exit 0
else
  echo "postup border gate FAIL"
  exit 1
fi
