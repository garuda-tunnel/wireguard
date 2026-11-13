#!/bin/bash
# WireGuard PostUp script.
#
# Architecture:
#   - MSS clamp is installed unconditionally.  Path-MTU through any WG
#     tunnel is smaller than the negotiated TCP MSS by default; without
#     clamping, large segments black-hole.  This is independent of
#     whether the container egresses traffic to the public internet.
#   - NAT (oifname "border" masquerade) and RPDB steering are installed
#     only when the "border" interface is present on the pod. Internal-mesh
#     participants (no border) install no NAT and no RPDB so that source
#     IPs propagate through the backbone untouched — required for
#     identity-aware features such as the pinning portal at 1.1.1.1:1111.
#
# Operators deploying the role outside the standard Garuda topology
# can layer additional rules via WG_POST_UP (already injected into the
# wg-quick conf by entrypoint.sh, before this script runs).

set -e

TABLE_NAME="border_${WG_INTERFACE}"

# --- Block 1: nft table base + MSS clamp ---
# Outbound (oifname) clamp-to-route-PMTU is unconditional: path-MTU through any
# WG tunnel is smaller than the negotiated TCP MSS by default; without clamping
# large segments black-hole.
# Inbound (iifname) fixed-MSS clamp is gated on WG_MSS_CLAMP_ENABLED. Both
# values (WG_FIXED_MSS, WG_MSS_CLAMP_ENABLED) are always injected by the chart.
nft add table inet "$TABLE_NAME" 2>/dev/null || true
nft delete table inet "$TABLE_NAME" 2>/dev/null || true

# Normalise WG_MSS_CLAMP_ENABLED: treat any value that is not "true" (case-insensitive)
# as disabled. The Helm template always injects the var so the unset case is not
# expected in production, but guard it for safety.
_clamp_enabled=0
case "${WG_MSS_CLAMP_ENABLED:-false}" in
    [Tt][Rr][Uu][Ee]) _clamp_enabled=1 ;;
esac

nft -f - <<EOF
table inet ${TABLE_NAME} {
    chain forward {
        type filter hook forward priority mangle; policy accept;
        oifname "${WG_INTERFACE}" tcp flags syn tcp option maxseg size set rt mtu
$( [ "$_clamp_enabled" -eq 1 ] && printf '        iifname "%s" tcp flags syn tcp option maxseg size set %s\n' "${WG_INTERFACE}" "${WG_FIXED_MSS}" )
    }
}
EOF

if [ "$_clamp_enabled" -eq 1 ]; then
    echo "[POSTUP] MSS clamp applied: oifname rt-mtu + iifname ${WG_FIXED_MSS} in table ${TABLE_NAME}"
else
    echo "[POSTUP] MSS clamp applied: oifname rt-mtu only (WG_MSS_CLAMP_ENABLED not true)"
fi

# --- Block 2: gate on border interface presence ---
if ! ip link show border >/dev/null 2>&1; then
    echo "[POSTUP] border interface not present — skipping NAT and RPDB"
    exit 0
fi

# --- Block 3: nft NAT + conntrack hygiene (border only) ---
# Append the postrouting chain to the existing table.  oifname
# "border" only: backbone is internal mesh, never masqueraded.
#
# The private_dst set is referenced by BOTH the postrouting return
# and the ct-timeout rule, so the timeout assignment cannot drift
# from "exactly the flows we masquerade out border".
#
# Masquerade applies only to conntrack-tracked packets, so two gaps
# exist for half-closed TCP flows (pod /proc/sys is read-only and
# net.netfilter.* is not in the kubelet allowed-unsafe-sysctls):
#   * ct timeout raises close_wait from the kernel default 60 s to
#     3600 s (the kube-proxy host value) for exactly the TCP flows
#     the postrouting rule masquerades out border; a client holding
#     a half-closed socket for minutes no longer outlives the entry,
#     so its late FIN is NATed and the server sees a clean teardown.
#     Unlisted TCP states keep the netns defaults.  The object is
#     IPv4 only (l3proto ip); IPv6 flows keep the netns defaults.
#     The forward chain runs before conntrack confirmation
#     (postrouting INT_MAX), where ct timeout set still applies; on
#     confirmed entries it is a no-op (kernel nft_ct_timeout_obj_eval).
#   * Whatever still arrives ct state invalid (no entry, e.g. after
#     the entry is lost) would leave border un-NATed with the
#     client's RFC1918 source; the host rp_filter drops it and logs
#     "martian source" (~9k lines/day on the busiest edge).  Drop it
#     in the pod instead — no live flow changes, only leak hygiene.
#     No legitimate flow is ever INVALID (new = SYN/NEW, established
#     retransmits = ESTABLISHED), so this is safe on every pod that
#     attaches border, hub included.
#
# Block 3 runs everywhere `border` is attached — k3s edge pods AND
# the mini-site hub per-edge wg pods (same Multus border NAD; their
# border carries the same edge->internet transit steered by RPDB
# border_egress, and their locally-originated control traffic — OSPF
# on backbone/wg — leaves via the output hook, never forward) — plus
# the compose hub stack:
#   * Compose hub stack — `border` is a docker bridge network; the
#     host adds a MASQUERADE rule on eth0 for traffic egressing the
#     bridge, so this in-container rule and the host rule chain
#     together to deliver the packet to the internet.
#   * k3s pod (edge or hub) — `border` is a Multus
#     NetworkAttachmentDefinition backed by a Linux bridge plugin
#     configured with isGateway=true, ipMasq=true. The bridge plugin
#     itself owns the host-side iptables MASQUERADE rule (see
#     modules/garuda_k8s/charts/garuda/templates/nad-border.yaml),
#     so packets that leave the pod via `border` are masqueraded by
#     CNI before they hit the VM's primary NIC.
# Deployments without border (internal-mesh participants; the
# mini-site hub-ros wg pod is backbone-only) never reach this block.
nft -f - <<EOF
table inet ${TABLE_NAME} {
    set private_dst {
        type ipv4_addr
        flags interval
        elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 }
    }
    ct timeout border_tcp_timeout {
        protocol tcp;
        l3proto ip;
        policy = { close_wait : 3600 }
    }
    chain forward_border {
        type filter hook forward priority filter; policy accept;
        oifname "border" ct state invalid drop
        oifname "border" ip protocol tcp ip daddr != @private_dst ct timeout set "border_tcp_timeout"
    }
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip daddr @private_dst return
        oifname "border" masquerade
    }
}
EOF

echo "[POSTUP] border masquerade applied in table ${TABLE_NAME}"

# --- Block 4: RPDB via_tunnel (border only) ---
# Backbone-ingress transit traffic is directed into the WG tunnel
# instead of the local default route.  Locally-originated traffic
# (OSPF, health checks) is unaffected because the iif match only
# fires on forwarded packets.

mkdir -p /etc/iproute2
touch /etc/iproute2/rt_tables
grep -q '^101 via_tunnel$' /etc/iproute2/rt_tables \
    || echo '101 via_tunnel' >> /etc/iproute2/rt_tables
grep -q '^102 border_egress$' /etc/iproute2/rt_tables \
    || echo '102 border_egress' >> /etc/iproute2/rt_tables

ip rule add pref 99 iif backbone lookup via_tunnel 2>/dev/null || true
ip route replace table via_tunnel default dev "$WG_INTERFACE"

# Keep intra-backbone traffic local (not tunneled).
BACKBONE_NET=$(ip -4 route list dev backbone scope link | head -1 | awk '{print $1}')
if [ -n "$BACKBONE_NET" ]; then
    ip route replace table via_tunnel "$BACKBONE_NET" dev backbone
fi

echo "[POSTUP] RPDB via_tunnel configured: iif backbone -> dev ${WG_INTERFACE}"

# Tunnel-ingress transit traffic is directed to the border interface so
# the edge CNI bridge can apply its host-side masquerade. Private
# destinations deliberately throw back to the main table so internal
# routes learned by OSPF keep their normal next hop.
ip rule add pref 98 iif "$WG_INTERFACE" lookup border_egress 2>/dev/null || true
ip route replace table border_egress throw 10.0.0.0/8
ip route replace table border_egress throw 172.16.0.0/12
ip route replace table border_egress throw 192.168.0.0/16
ip route replace table border_egress throw 100.64.0.0/10
BORDER_CIDR=$(ip -4 route list dev border scope link | awk 'NR == 1 { print $1 }')
BORDER_NET=${BORDER_CIDR%/*}
IFS=. read -r BORDER_A BORDER_B BORDER_C BORDER_D <<EOF
${BORDER_NET}
EOF
BORDER_INT=$(( (BORDER_A << 24) + (BORDER_B << 16) + (BORDER_C << 8) + BORDER_D + 1 ))
BORDER_GW="$(( (BORDER_INT >> 24) & 255 )).$(( (BORDER_INT >> 16) & 255 )).$(( (BORDER_INT >> 8) & 255 )).$(( BORDER_INT & 255 ))"
ip route replace table border_egress default via "$BORDER_GW" dev border

echo "[POSTUP] RPDB border_egress configured: iif ${WG_INTERFACE} -> dev border"
