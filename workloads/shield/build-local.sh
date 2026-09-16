#!/usr/bin/env sh
set -eu

usage() {
  printf 'usage: %s <jheem_analyses-path> <jheem2-path> [recorded|development] [tag]\n' "$0" >&2
  exit 64
}

[ "$#" -ge 2 ] && [ "$#" -le 4 ] || usage

analyses_path="$1"
jheem2_path="$2"
target="${3:-recorded}"

[ "$target" = "recorded" ] || [ "$target" = "development" ] || usage

for path in "$analyses_path" "$jheem2_path"; do
  git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { printf 'not a Git worktree: %s\n' "$path" >&2; exit 65; }
  [ -z "$(git -C "$path" status --porcelain --untracked-files=normal)" ] \
    || { printf 'source worktree must be clean: %s\n' "$path" >&2; exit 65; }
done

analyses_ref="$(git -C "$analyses_path" rev-parse HEAD)"
jheem2_ref="$(git -C "$jheem2_path" rev-parse HEAD)"
default_tag="jheem-shield:${target}-$(printf '%.12s' "$analyses_ref")"
tag="${4:-$default_tag}"

printf 'Building %s\n' "$tag"
printf '  jheem_analyses: %s\n' "$analyses_ref"
printf '  jheem2:         %s\n' "$jheem2_ref"

docker buildx build \
  --progress plain \
  --load \
  --target "$target" \
  --build-context "jheem_analyses=$analyses_path" \
  --build-context "jheem2=$jheem2_path" \
  --build-arg "JHEEM_ANALYSES_REF=$analyses_ref" \
  --build-arg "JHEEM2_REF=$jheem2_ref" \
  --tag "$tag" \
  "$(dirname "$0")"
