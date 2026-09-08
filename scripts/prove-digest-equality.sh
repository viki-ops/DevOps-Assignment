#!/usr/bin/env bash
# Prove the same image digests are pinned across dev/stage/prod values.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
services=(ui catalog cart checkout orders)
envs=(dev stage prod)
fail=0
echo "== digest equality across environments =="
for svc in "${services[@]}"; do
  declare -A digests=()
  for env in "${envs[@]}"; do
    dig=$(awk '/^image:/{f=1} f&&/digest:/{print $2; exit}' "$root/gitops/values/apps/$env/$svc.yaml")
    digests[$env]=$dig
  done
  if [[ "${digests[dev]}" == "${digests[stage]}" && "${digests[stage]}" == "${digests[prod]}" && -n "${digests[dev]}" ]]; then
    echo "OK  $svc  ${digests[dev]}"
  else
    echo "FAIL $svc  dev=${digests[dev]} stage=${digests[stage]} prod=${digests[prod]}"
    fail=1
  fi
done
exit $fail
