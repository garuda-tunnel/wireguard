#!/usr/bin/env bash
# Helm-level tests for modules/wireguard/kube.
# helm lint + helm template diffed against tests/golden/*.yaml.
# Update goldens with: REGEN_GOLDEN=1 ./run-helm-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/../.."
CHART_DIR="${MODULE_DIR}/charts/wireguard"
GOLDEN_DIR="${SCRIPT_DIR}/../golden"

# Resolve the frr-sidecar library dependency from OCI (Chart.yaml lists
# it via `oci://ghcr.io/alexmkx/charts`). Without this step `helm template` fails
# with "no cached repo found" on a clean checkout. The Terraform Helm
# provider performs the equivalent step automatically via
# `dependency_update = true` on helm_release.
helm dependency update "${CHART_DIR}"

for scenario in default with-ospf with-transit-provider; do
  values_file="${SCRIPT_DIR}/values-${scenario}.yaml"
  helm lint "${CHART_DIR}" -f "${values_file}"

  out="$(helm template wg "${CHART_DIR}" --namespace garuda -f "${values_file}")"
  golden="${GOLDEN_DIR}/${scenario}.yaml"

  if [[ "${REGEN_GOLDEN:-0}" == "1" ]]; then
    printf '%s\n' "${out}" > "${golden}"
    echo "regenerated ${golden}"
    continue
  fi

  if ! diff -u "${golden}" <(printf '%s\n' "${out}"); then
    echo "golden mismatch for ${scenario}" >&2
    exit 1
  fi

  echo "ok: ${scenario}"
done

# MTU alignment: wireguard.mtu must render as WG_MTU env var in the deployment.
mtu_scenario="mtu-1330"
helm lint "${CHART_DIR}" -f "${SCRIPT_DIR}/values-${mtu_scenario}.yaml"
mtu_out="$(helm template wg "${CHART_DIR}" --namespace garuda -f "${SCRIPT_DIR}/values-${mtu_scenario}.yaml")"
mtu_golden="${GOLDEN_DIR}/${mtu_scenario}.yaml"

if ! echo "${mtu_out}" | grep -q 'WG_MTU'; then
  echo "FAIL: WG_MTU env var missing from deployment when wireguard.mtu is set" >&2
  exit 1
fi

if ! echo "${mtu_out}" | grep -q '"1330"'; then
  echo "FAIL: MTU value 1330 not found in deployment env" >&2
  exit 1
fi

if [[ "${REGEN_GOLDEN:-0}" == "1" ]]; then
  printf '%s\n' "${mtu_out}" > "${mtu_golden}"
  echo "regenerated ${mtu_golden}"
elif [[ -f "${mtu_golden}" ]]; then
  if ! diff -u "${mtu_golden}" <(printf '%s\n' "${mtu_out}"); then
    echo "golden mismatch for ${mtu_scenario}" >&2
    exit 1
  fi
fi

echo "ok: ${mtu_scenario}"

# MTU alignment: default golden must NOT include WG_MTU (wireguard.mtu: null,
# so the image uses its kernel default, preserving existing deployments).
default_out="$(helm template wg "${CHART_DIR}" --namespace garuda -f "${SCRIPT_DIR}/values-default.yaml")"
if echo "${default_out}" | grep -q 'WG_MTU'; then
  echo "FAIL: WG_MTU must NOT appear in default deployment (wireguard.mtu not set)" >&2
  exit 1
fi

echo "ok: default-no-mtu"
