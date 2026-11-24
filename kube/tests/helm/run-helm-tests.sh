#!/usr/bin/env bash
# Helm-level tests for modules/wireguard/kube.
# helm lint + helm template diffed against tests/golden/*.yaml.
# Update goldens with: REGEN_GOLDEN=1 ./run-helm-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/../.."
CHART_DIR="${MODULE_DIR}/charts/wireguard"
GOLDEN_DIR="${SCRIPT_DIR}/../golden"

# Resolve chart dependencies (Chart.yaml may list library charts from OCI).
# Without this step `helm template` fails with "no cached repo found" on a
# clean checkout. The Terraform Helm provider performs the equivalent step
# automatically via `dependency_update = true` on helm_release.
helm dependency update "${CHART_DIR}"

for scenario in default; do
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

# Negative checks: the chart must refuse to render without the module-provided
# keys (peer.listen_port, mtuPolicy). An overlay file with null deletes the
# key from the merged values (unlike --set key=null, which leaves an explicit
# null), so the schema must reject each render. The last check catches
# test-only defaults creeping back into values.yaml: with no values file the
# chart alone must not satisfy its own schema.
if helm template wg "${CHART_DIR}" --namespace garuda -f "${SCRIPT_DIR}/values-default.yaml" \
    -f <(printf 'peer:\n  listen_port: null\n') >/dev/null 2>&1; then
  echo "FAIL: render succeeded without peer.listen_port; schema must reject it" >&2
  exit 1
fi
echo "ok: negative peer.listen_port"

if helm template wg "${CHART_DIR}" --namespace garuda -f "${SCRIPT_DIR}/values-default.yaml" \
    -f <(printf 'mtuPolicy: null\n') >/dev/null 2>&1; then
  echo "FAIL: render succeeded without mtuPolicy; schema must reject it" >&2
  exit 1
fi
echo "ok: negative mtuPolicy"

if helm template wg "${CHART_DIR}" --namespace garuda >/dev/null 2>&1; then
  echo "FAIL: render succeeded with no values file; values.yaml must not default schema-required keys" >&2
  exit 1
fi
echo "ok: negative no-values"
