#!/usr/bin/env bash
# Verifies postup.sh Block-2 gates on `ip link show border` (interface
# presence), NOT on the removed WG_NIC_ATTACH env. Stubs nft (captures the
# rulesets fed via -f) and
# ip: `link show border` returns success/failure per case, and `-4 route
# list dev <backbone|border> scope link` returns realistic single-line
# CIDR output (RFC5737 TEST-NET ranges) so the RPDB gateway computation in
# Blocks 3-4 actually succeeds instead of operating on empty input.
#
# The border-present case does NOT swallow postup.sh's exit code: it
# requires exit 0 and asserts the NAT log line plus BOTH RPDB completion
# log lines (via_tunnel and border_egress), so a failure anywhere in the
# RPDB setup (Blocks 3-4) fails the test instead of passing silently.
# It also asserts the Block-3 border-only conntrack hygiene: the
# `oifname "border" ct state invalid drop` rule and the close_wait
# timeout object assigned with `ct timeout set` are present when border
# exists and absent otherwise (deployments without border — internal-mesh
# participants, backbone-only guests such as the mini-site hub-ros wg pod
# — must not get them; the Block-2 gate, not a hub-vs-edge distinction).
#
# Beyond grep: the border-present ruleset is loaded with a real nftables
# kernel via `unshare -rn nft -c -f` (isolated unprivileged user+net
# namespace — no root, no host netns mutation), so a ruleset that fails
# to parse or load cannot pass. Skipped with a message where nft or
# unprivileged user namespaces are unavailable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0

# Sets up nft/ip stubs in a fresh tmp dir and prints its path.
#   $1 — exit code `ip link show border` should return (0=present, 1=absent)
# The nft stub appends every `-f -` payload to $NFT_CAPTURE (both the
# Block-1 and Block-3 heredocs), so the generated ruleset is assertable.
setup_stubs() {
  local border_present="$1"
  local TMP; TMP=$(mktemp -d)
  cat > "$TMP/nft" <<'NFT'
#!/usr/bin/env bash
if [ "${1:-}" = "-f" ] && [ -n "${NFT_CAPTURE:-}" ]; then
  cat >> "$NFT_CAPTURE"
fi
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
export NFT_CAPTURE="$TMP/nft-ruleset"; : > "$NFT_CAPTURE"
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
  # Border conntrack hygiene (Block 3): INVALID drop + close_wait timeout.
  # private_dst must be a named set referenced by BOTH the postrouting
  # return and the ct-timeout rule (drift prevention: the timeout keeps
  # covering exactly the flows the postrouting rule masquerades).
  for expect in \
    "oifname \"border\" ct state invalid drop" \
    "policy = { close_wait : 3600 }" \
    "ct timeout set \"border_tcp_timeout\"" \
    "set private_dst {" \
    "ip daddr @private_dst return" \
    "ip daddr != @private_dst"
  do
    if ! grep -qF "$expect" "$NFT_CAPTURE"; then
      echo "FAIL: border present (expected ruleset to contain '${expect}')"; cat "$NFT_CAPTURE"
      case_ok=0; FAIL=1
    fi
  done
  # Behavioral check: the captured ruleset must load into a real
  # nftables kernel, not merely contain the expected strings. Runs in
  # an isolated unprivileged user+net namespace; skip (not fail) where
  # nft or unprivileged user namespaces are unavailable.
  if command -v nft >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
     && unshare -rn true >/dev/null 2>&1; then
    if unshare -rn nft -c -f "$NFT_CAPTURE" 2>"$TMP/nft-load-err"; then
      echo "PASS: border-present ruleset loads (unshare -rn nft -c -f)"
    else
      echo "FAIL: border-present ruleset rejected by nft -c:"; cat "$TMP/nft-load-err"; cat "$NFT_CAPTURE"
      FAIL=1
    fi
  else
    echo "SKIP: ruleset load check (nft or unprivileged user namespaces unavailable)"
  fi
  [ "$case_ok" -eq 1 ] && echo "PASS: border present installs NAT and completes RPDB setup"
fi
rm -rf "$TMP"

# --- Case: border absent -> legitimate clean exit 0, NAT/RPDB skipped ---
TMP="$(setup_stubs 1)"
saved_path="$PATH"; export PATH="$TMP:$PATH"
export WG_INTERFACE="wg-test" WG_FIXED_MSS="1290" WG_MSS_CLAMP_ENABLED="true"
export NFT_CAPTURE="$TMP/nft-ruleset"; : > "$NFT_CAPTURE"
LOG="$TMP/log"
set +e
bash "${SCRIPT_DIR}/../image/postup.sh" > "$LOG" 2>&1
RC=$?
set -e
export PATH="$saved_path"
if [ "$RC" -ne 0 ]; then
  echo "FAIL: border absent must exit 0, got ${RC}"; cat "$LOG"; FAIL=1
elif grep -qF "border interface not present" "$LOG"; then
  if grep -qE "ct state invalid|ct timeout" "$NFT_CAPTURE"; then
    echo "FAIL: border absent must not emit border conntrack rules"; cat "$NFT_CAPTURE"
    FAIL=1
  else
    echo "PASS: border absent skips NAT"
  fi
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
