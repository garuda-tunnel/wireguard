# AGENTS.md

Security and contribution rules for garuda-wireguard.

## Security

- Never commit or use real public IP addresses. Use RFC5737 (TEST-NET) / RFC1918 / CGNAT ranges only.
- Never commit or use domains other than well-known examples or `example.net`.
- Never commit secrets, tokens, private keys, or customer data.

## Garuda platform rules

This repo is part of garuda-tunnel. Platform rules (annotation-layer design, MAP/VAP
injection engine, `garuda_guest` contract, vanilla guest contract, bootstrap timing,
Multus attach-race fix, anti-patterns):

**See: https://github.com/garuda-tunnel/garuda/blob/main/docs/AGENTS-platform.md**
Local path: `../garuda/docs/AGENTS-platform.md`

## Naming

This repo is `garuda-wireguard`; its image is `ghcr.io/garuda-tunnel/garuda-wireguard`;
its chart is `oci://ghcr.io/garuda-tunnel/charts/wireguard`. The chart `version` in
`kube/charts/wireguard/Chart.yaml` MUST equal the git tag.

## WireGuard-specific notes

- `net.ipv4.conf.all.src_valid_mark = 1` is a pod-level sysctl that stays in this
  chart's own `securityContext` (app-intrinsic — WireGuard requires it for routing mark
  validation). Garuda's MAP injects `ip_forward` and `rp_filter` at the pod level;
  `src_valid_mark` is NOT injected by garuda — it is declared in the guest chart.
- This module is a **vanilla guest**: it accepts `annotations`, `labels`, `configmaps`
  map inputs and has zero garuda knowledge. See platform rules for the full contract.
