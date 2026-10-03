#!/usr/bin/env bash
# Two fresh, network-isolated processes in the same image. No MCMC or live state.
set -euo pipefail
[[ $# == 5 ]] || { echo "usage: $0 IMAGE ANALYSES_CHECKOUT ENGINE_CHECKOUT CACHE NEW_OUTPUT" >&2; exit 64; }
image=$(docker image inspect --format '{{.Id}}' "$1")
analyses=$(cd "$2" && pwd -P)
engine=$(cd "$3" && pwd -P)
cache=$(cd "$4" && pwd -P)
output=$5
[[ ! -e "$output" && -d "$(dirname "$output")" ]] || { echo "Choose a new output directory" >&2; exit 65; }
[[ ! -e "${output}.native-sources" ]] || { echo "Native diagnostic copy already exists" >&2; exit 65; }
for checkout in "$analyses" "$engine"; do
  [[ -z $(git -C "$checkout" status --porcelain) ]] || { echo "Source must be clean: $checkout" >&2; exit 65; }
  # Copies must retain usable Git metadata, not an external worktree pointer.
  [[ -d "$checkout/.git" ]] || { echo "Use standalone Git checkouts" >&2; exit 65; }
done
analyses_ref=$(git -C "$analyses" rev-parse HEAD)
engine_ref=$(git -C "$engine" rev-parse HEAD)
[[ $(docker image inspect --format '{{index .Config.Labels "org.jheem.shield.jheem-analyses-ref"}}' "$image") == "$analyses_ref" ]]
[[ $(docker image inspect --format '{{index .Config.Labels "org.jheem.shield.jheem2-ref"}}' "$image") == "$engine_ref" ]]
mkdir "$output"
output=$(cd "$output" && pwd -P)
# Keep the source copy outside the writable report mount. Otherwise its files
# would also be writable through /comparison-output/native despite a read-only
# source mount at /comparison/jheem_analyses.
mkdir "${output}.native-sources" "$output/package-state" "$output/native-state"
cp -R "$analyses" "${output}.native-sources/jheem_analyses"
script_dir=$(cd "$(dirname "$0")" && pwd -P)
python3 "$script_dir/compare_fixed_parameters.py" prepare-native \
  "${output}.native-sources/jheem_analyses" "$output/bootstrap-adaptation.json"
docker image inspect --format '{{.Id}}' "$image" > "$output/image-id.txt"

run_check() {
  local mode=$1 source=$2 state=$3 report=$4 fixture_env=$5
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$source,dst=/comparison/jheem_analyses,readonly" \
    --mount "type=bind,src=$engine,dst=/comparison/jheem2,readonly" \
    --mount "type=bind,src=$cache,dst=/work/cache,readonly" \
    --mount "type=bind,src=$output,dst=/comparison-output" \
    --env JHEEM_ANALYSES_PATH=/comparison/jheem_analyses \
    --env JHEEM2_PATH=/comparison/jheem2 --env "JHEEM2_MODE=$mode" \
    --env "JHEEM_ROOT_DIR=/comparison-output/$state" --env SHIELD_RUN_MODE=fresh \
    --env JHEEM_CENSUS_MANAGER_TAG=data-managers-v2026.08.26 \
    --env JHEEM_SYPHILIS_MANAGER_TAG=syphilis-manager-v2026.09.09 \
    --env SHIELD_RANDOM_SEED=0 --env SHIELD_COMPARE_TRAJECTORIES=true \
    --env "$fixture_env=/comparison-output/parameters.rds" \
    --env "SHIELD_COMPARISON_REPORT=/comparison-output/$report" \
    "$image" shell -c '
      R_LIBS="$(Rscript -e '\''writeLines(paste(.libPaths(), collapse = ":"))'\'' | tail -n 1)"
      export R_LIBS
      cd "$JHEEM_ANALYSES_PATH"
      Rscript --vanilla applications/SHIELD/tests/check-stage1-compatibility.R "$SHIELD_COMPARISON_REPORT"
    '
}
run_check package "$analyses" package-state package-report SHIELD_SAVE_PARAMETERS \
  > "$output/package.log" 2>&1
run_check source "${output}.native-sources/jheem_analyses" native-state native-report SHIELD_COMPARISON_PARAMETERS \
  > "$output/native.log" 2>&1
python3 "$script_dir/compare_fixed_parameters.py" compare \
  "$output/package-report/report.json" "$output/native-report/report.json" \
  "$output/bootstrap-adaptation.json" "$output/comparison.json" | tee "$output/summary.txt"
[[ -z $(ls -A "$output/package-state") && -z $(ls -A "$output/native-state") ]]
