#!/usr/bin/env bash
# Render every ArgoCD Application under applications/ via `helm template`
# using the repo's value files, then pipe the result into kubeconform.
#
# Assumes the three-source ArgoCD pattern documented in CLAUDE.md:
#   source[0] -> Helm chart (repoURL + chart + targetRevision + valueFiles)
#   source[1] -> this repo, ref: values  (local value files)
#   source[2] -> this repo, path: manifests/{ns}/{app}  (Kustomize overlay)
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCHEMA_LOCATIONS=(
  "default"
  "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json"
)

fail=0
rendered=0
skipped=0

mapfile -t APPS < <(find "$REPO_ROOT/applications" -type f -name '*.yaml' ! -name 'aoa.yaml' | sort)

for app in "${APPS[@]}"; do
  rel="${app#$REPO_ROOT/}"
  kind="$(yq -r '.kind // ""' "$app")"
  [[ "$kind" != "Application" ]] && { echo "::notice::skip non-Application $rel"; skipped=$((skipped+1)); continue; }

  chart_repo="$(yq -r '.spec.sources[0].repoURL // ""' "$app")"
  chart_name="$(yq -r '.spec.sources[0].chart // ""' "$app")"
  chart_ver="$(yq -r '.spec.sources[0].targetRevision // ""' "$app")"
  namespace="$(yq -r '.spec.destination.namespace // "default"' "$app")"
  name="$(yq -r '.metadata.name' "$app")"

  if [[ -z "$chart_name" ]]; then
    echo "::notice::skip $rel (no helm chart in sources[0])"
    skipped=$((skipped+1))
    continue
  fi

  # Collect -f value files, rewriting $values/ to repo root.
  values_args=()
  while IFS= read -r vf; do
    [[ -z "$vf" ]] && continue
    path="${vf/\$values\//$REPO_ROOT/}"
    if [[ -f "$path" ]]; then
      values_args+=("-f" "$path")
    else
      echo "::warning file=$rel::value file not found: $vf"
    fi
  done < <(yq -r '.spec.sources[0].helm.valueFiles[]? // ""' "$app")

  # Build chart reference. OCI registries need the oci:// prefix.
  if [[ "$chart_repo" == oci://* || "$chart_repo" == docker.io/* || "$chart_repo" == ghcr.io/* || "$chart_repo" == quay.io/* ]]; then
    chart_ref="oci://${chart_repo#oci://}/$chart_name"
    helm_args=(template "$name" "$chart_ref" --version "$chart_ver" --namespace "$namespace")
  else
    helm_args=(template "$name" "$chart_name" --repo "$chart_repo" --version "$chart_ver" --namespace "$namespace")
  fi
  helm_args+=("${values_args[@]}")

  echo "=== rendering $rel ==="
  out="$(mktemp)"
  if ! helm "${helm_args[@]}" > "$out" 2> "$out.err"; then
    echo "::error file=$rel::helm template failed"
    cat "$out.err"
    fail=$((fail+1))
    continue
  fi

  kubeconform_args=(-ignore-missing-schemas -summary)
  if [[ -n "${KUBECONFORM_SKIP:-}" ]]; then
    kubeconform_args+=(-skip "$KUBECONFORM_SKIP")
  fi
  for loc in "${SCHEMA_LOCATIONS[@]}"; do
    kubeconform_args+=(-schema-location "$loc")
  done

  if ! kubeconform "${kubeconform_args[@]}" < "$out"; then
    echo "::error file=$rel::kubeconform validation failed"
    fail=$((fail+1))
    continue
  fi
  rendered=$((rendered+1))
done

echo "Rendered: $rendered  Skipped: $skipped  Failed: $fail"
exit "$fail"
