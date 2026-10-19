#!/usr/bin/env bash
# Build a jheem2 commit inside the runtime image, the way captured engines are
# built for runs, and run that commit's tests/*.R against the build.
#   test_jheem2_ref.sh <image> <jheem2 ref>
set -euo pipefail
image="$1" ref="$2"
[[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || { echo "invalid jheem2 ref: $ref" >&2; exit 1; }
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone -q https://github.com/CIPHER-Epi/jheem2.git "$work/jheem2"
git -C "$work/jheem2" checkout -q "$ref"
commit="$(git -C "$work/jheem2" rev-parse HEAD)"
echo "Testing jheem2 $ref ($commit)"
shopt -s nullglob
tests=("$work"/jheem2/tests/*.R)
if (( ${#tests[@]} == 0 )); then
  echo "jheem2 $commit has no tests/*.R; nothing to run."
  exit 0
fi
mkdir "$work/build"
docker run --rm --network none --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$work/jheem2,dst=/opt/run-engine/jheem2,readonly" \
  --mount "type=bind,src=$work/build,dst=/opt/run-engine/build" \
  --mount "type=bind,src=$here/build_engine.sh,dst=/opt/shield/build_engine.sh,readonly" \
  "$image" shell -c '
    set -euo pipefail
    bash /opt/shield/build_engine.sh
    cd /app
    export RENV_CONFIG_SYNCHRONIZED_CHECK=FALSE JHEEM2_TEST_LIBRARY=/opt/run-engine/build
    for test in /opt/run-engine/jheem2/tests/*.R; do
      echo "== $(basename "$test")"
      Rscript "$test"
    done'
echo "jheem2 $commit: all ${#tests[@]} test file(s) passed"
