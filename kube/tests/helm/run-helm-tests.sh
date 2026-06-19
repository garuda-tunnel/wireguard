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

# MTU alignment: mtuPolicy.* must render as WG_EFFECTIVE_MTU/WG_FIXED_MSS/WG_MSS_CLAMP_ENABLED
# env vars in the deployment. No legacy WG_MTU.
mtu_scenario="mtu-1330"
helm lint "${CHART_DIR}" -f "${SCRIPT_DIR}/values-${mtu_scenario}.yaml"
mtu_out="$(helm template wg "${CHART_DIR}" --namespace garuda -f "${SCRIPT_DIR}/values-${mtu_scenario}.yaml")"
mtu_golden="${GOLDEN_DIR}/${mtu_scenario}.yaml"

if ! echo "${mtu_out}" | grep -q 'WG_EFFECTIVE_MTU'; then
  echo "FAIL: WG_EFFECTIVE_MTU env var missing from deployment when mtuPolicy.effectiveMtu is set" >&2
  exit 1
fi

if ! echo "${mtu_out}" | grep -q 'WG_FIXED_MSS'; then
  echo "FAIL: WG_FIXED_MSS env var missing from deployment when mtuPolicy.fixedMss is set" >&2
  exit 1
fi

if ! echo "${mtu_out}" | grep -q 'WG_MSS_CLAMP_ENABLED'; then
  echo "FAIL: WG_MSS_CLAMP_ENABLED env var missing from deployment when mtuPolicy.mssClampEnabled is set" >&2
  exit 1
fi

if ! echo "${mtu_out}" | grep -q '"1330"'; then
  echo "FAIL: effectiveMtu value 1330 not found in deployment env" >&2
  exit 1
fi

if ! echo "${mtu_out}" | grep -q '"1290"'; then
  echo "FAIL: fixedMss value 1290 not found in deployment env" >&2
  exit 1
fi

if echo "${mtu_out}" | grep -q 'WG_MTU'; then
  echo "FAIL: legacy WG_MTU must NOT appear in deployment (replaced by WG_EFFECTIVE_MTU)" >&2
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

# mtuPolicy env vars must appear in default deployment too (always unconditional).
default_out="$(helm template wg "${CHART_DIR}" --namespace garuda -f "${SCRIPT_DIR}/values-default.yaml")"
if ! echo "${default_out}" | grep -q 'WG_EFFECTIVE_MTU'; then
  echo "FAIL: WG_EFFECTIVE_MTU must appear in default deployment (mtuPolicy always rendered)" >&2
  exit 1
fi
if echo "${default_out}" | grep -q 'WG_MTU'; then
  echo "FAIL: legacy WG_MTU must NOT appear in default deployment" >&2
  exit 1
fi

echo "ok: default-mtu-policy"
