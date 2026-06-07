# garuda-wireguard

Terraform module + Helm chart + image for WireGuard endpoints in the Garuda topology.

- Terraform module: `kube/` — consume via `git::https://github.com/garuda-tunnel/garuda-wireguard.git//kube?ref=vX.Y.Z`.
- Helm chart: `oci://ghcr.io/garuda-tunnel/charts/wireguard` (published on tag push).
- Image: `ghcr.io/garuda-tunnel/garuda-wireguard` (semver + `:latest` + `:sha-...`).

Additional subdirectories: `routeros/` contains the MikroTik RouterOS Terraform module for the WireGuard peer side; `tunnel/` contains the tunnel data model module shared between `kube/` and `routeros/`. See `kube/README.md` for module inputs/outputs and `AGENTS.md` for the FRR-sidecar reuse rule.
