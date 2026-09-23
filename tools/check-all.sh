#!/usr/bin/env bash
# Every gate, one command, and the exit code survives.
#
# This exists because a failing checklist got committed once: the chain was
# `./tools/security-check.sh | tail -2 && git commit`, and a pipe hands you
# `tail`'s exit code, not the script's. Nothing here is piped.
set -euo pipefail

cd "$(dirname "$0")/.."

run() {
  printf '\n\033[1m%s\033[0m\n' "$1"
  shift
  "$@"
}

run "dictionaries"   ./tools/check-i18n.sh
run "sprites"        ./tools/check-sprites.sh
run "security"       ./tools/security-check.sh
run "weight"         ./tools/weight.sh
run "qmllint"        ./tools/lint.sh
run "rules"          node tests/rules.test.js
run "arena balance"  node tools/balance.js
run "manifest"       omarchy plugin validate .

printf '\n\033[1mall clear\033[0m\n'
