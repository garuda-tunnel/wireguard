# AGENTS.md

Security and contribution rules for garuda-wireguard.

## Security

- Never commit or use real public IP addresses. Use RFC5737 (TEST-NET) / RFC1918 / CGNAT ranges only.
- Never commit or use domains other than well-known examples or `example.net`.
- Never commit secrets, tokens, private keys, or customer data.

**Exception — pinning-portal anchor:** The literal `1.1.1.1:1111` is permitted in
**comments** that document the pinning-portal anchor address (e.g. in
`kube/image/postup.sh`). This address is an intentionally stable, operator-facing
anchor used to explain why backbone source IPs must propagate untouched through the
internal mesh. It is not a live DNS dependency and must never appear in executable
code paths (routing rules, nftables rules, configuration values, etc.).

## FRR sidecar reuse — architectural rule

This module consumes the `frr-sidecar` library Helm chart from OCI
(`oci://ghcr.io/garuda-tunnel/charts/frr-sidecar`, published by the external repo
`garuda-tunnel/garuda-frr-sidecar`). The consumer chart `kube/charts/wireguard/Chart.yaml`
declares it via `dependencies:` with `repository: "oci://ghcr.io/garuda-tunnel/charts"`
and a pinned `version`. The Terraform `helm_release` sets `dependency_update = true`
so Helm resolves the OCI dependency at apply time (unauthenticated for the public
ghcr package).

Anti-patterns (do NOT do this):
- Use `file://` form — it is OBSOLETE.
- Pin to a non-immutable tag (e.g. `latest`) — always pin to a specific semver version.
- Vendor the chart by copying it into consumer `charts/` directories.
- Inline copy of `frr-sidecar` container spec in consumer `deployment.yaml`.
- Local `<workload>.frrConf` helper duplicating `frr-sidecar.frrConf` rendering logic.

## Naming

This repo is `garuda-wireguard`; its image is `ghcr.io/garuda-tunnel/garuda-wireguard`;
its chart is `oci://ghcr.io/garuda-tunnel/charts/wireguard`. The chart `version` in
`kube/charts/wireguard/Chart.yaml` MUST equal the git tag.
