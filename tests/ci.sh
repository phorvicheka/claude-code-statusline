#!/usr/bin/env bash
# tests/ci.sh — everything CI runs. The GitHub workflow calls only this script, so a local run is the same check.
#
#   bash tests/ci.sh            # run in this checkout
#   bash tests/ci.sh --fresh    # run in a fresh clone of HEAD (what CI sees; ignores uncommitted changes)
#
# Env: SUT_BASH=/bin/bash   run the shipped scripts under that bash (the macOS job uses 3.2)
#      CI_SHELLCHECK=1      shellcheck is required (the ubuntu job); otherwise it runs only if installed
set -eo pipefail

if [[ "${1:-}" == "--fresh" ]]; then
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    sha="$(git -C "$src" rev-parse HEAD)"
    [[ -z "$(git -C "$src" status --porcelain)" ]] || echo "note: uncommitted changes are NOT tested (fresh clone of ${sha:0:7})"
    work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
    git clone -q "$src" "$work/repo" && git -C "$work/repo" checkout -q "$sha"
    bash "$work/repo/tests/ci.sh"
    exit
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo "== env: $(uname -s) | bash $BASH_VERSION | SUT_BASH=${SUT_BASH:-bash} ($("${SUT_BASH:-bash}" -c 'echo $BASH_VERSION')) | $(jq --version) | $(git --version) | sha $(git rev-parse --short HEAD 2>/dev/null || echo n/a)"

scripts=(statusline.sh install.sh uninstall.sh tests/run.sh tests/ci.sh)
if command -v shellcheck >/dev/null 2>&1; then
    echo "== shellcheck"
    shellcheck -S warning "${scripts[@]}"
    echo "shellcheck: PASS"
elif [[ "${CI_SHELLCHECK:-}" == 1 ]]; then
    echo "shellcheck: required but not installed" >&2; exit 1
else
    echo "shellcheck: NOT RUN (not installed)"
fi

echo "== syntax (bash -n under ${SUT_BASH:-bash})"
for f in "${scripts[@]}"; do "${SUT_BASH:-bash}" -n "$f"; done
echo "syntax: PASS"

echo "== tests/run.sh"
bash tests/run.sh
