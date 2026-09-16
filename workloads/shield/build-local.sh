#!/usr/bin/env sh
set -eu

usage() {
  printf 'usage: %s <jheem_analyses-path> <jheem2-path> <locations-path> [recorded|development] [tag]\n' "$0" >&2
  exit 64
}

[ "$#" -ge 3 ] && [ "$#" -le 5 ] || usage

analyses_path="$1"
jheem2_path="$2"
locations_path="$3"
target="${4:-recorded}"

[ "$target" = "recorded" ] || [ "$target" = "development" ] || usage

for path in "$analyses_path" "$jheem2_path" "$locations_path"; do
  git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { printf 'not a Git worktree: %s\n' "$path" >&2; exit 65; }
  [ -z "$(git -C "$path" status --porcelain --untracked-files=normal)" ] \
    || { printf 'source worktree must be clean: %s\n' "$path" >&2; exit 65; }
done

analyses_ref="$(git -C "$analyses_path" rev-parse HEAD)"
jheem2_ref="$(git -C "$jheem2_path" rev-parse HEAD)"
locations_ref="$(git -C "$locations_path" rev-parse HEAD)"
default_tag="jheem-shield:${target}-$(printf '%.12s' "$analyses_ref")"
tag="${5:-$default_tag}"

printf 'Building %s\n' "$tag"
printf '  jheem_analyses: %s\n' "$analyses_ref"
printf '  jheem2:         %s\n' "$jheem2_ref"
printf '  locations:      %s\n' "$locations_ref"

docker buildx build \
  --progress plain \
  --load \
  --target "$target" \
  --build-context "jheem_analyses=$analyses_path" \
  --build-context "jheem2=$jheem2_path" \
  --build-context "locations=$locations_path" \
  --build-arg "JHEEM_ANALYSES_REF=$analyses_ref" \
  --build-arg "JHEEM2_REF=$jheem2_ref" \
  --build-arg "LOCATIONS_REF=$locations_ref" \
  --tag "$tag" \
  "$(dirname "$0")"
