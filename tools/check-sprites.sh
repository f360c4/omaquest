#!/usr/bin/env bash
# Every sprite is exactly 16 lines of 16 characters drawn from `X` and `.`,
# ends with a newline, and appears in index.json — and index.json names
# nothing that is not there.
#
# The grids are the repository's only artwork, and they are text precisely so
# that a reviewer can read them in a diff. That is worth nothing if a malformed
# one can ship, hence this.
set -euo pipefail

cd "$(dirname "$0")/../assets/sprites"

size=16
status=0

for file in *.txt; do
  lines=$(wc -l <"$file")
  if [ "$lines" -ne "$size" ]; then
    echo "$file: $lines lines, expected $size (or a missing final newline)" >&2
    status=1
    continue
  fi

  bad=$(grep -cvE "^[X.]{$size}\$" "$file" || true)
  if [ "$bad" -ne 0 ]; then
    echo "$file: $bad line(s) are not exactly $size characters of X and ." >&2
    grep -nvE "^[X.]{$size}\$" "$file" >&2 || true
    status=1
  fi
done

# Every name the code can ask for has to exist. `check-sprites` used to only
# compare the index against the directory, which both agreed on a sprite that
# was never drawn: `boss_daemon_idle_a` was missing for four phases, and every
# crash boss rendered as empty space with nobody noticing.
cd ../..
missing=""
for race in $(jq -r '.[]' <<<'["human","dwarf","elf","orc","automaton"]'); do
  for frame in a b; do
    [ -f "assets/sprites/${race}_idle_${frame}.txt" ] || missing="$missing ${race}_idle_${frame}"
  done
done
for cls in warrior rogue bard druid mage archer; do
  [ -f "assets/sprites/${cls}_gear_a.txt" ] || missing="$missing ${cls}_gear_a"
done
for fx in fx_sleep_a fx_sleep_b fx_cheer_a fx_cheer_b; do
  [ -f "assets/sprites/${fx}.txt" ] || missing="$missing $fx"
done
# The bestiary, as game/Rules.js lists it, plus the two bosses the arena draws.
for enemy in $(grep -oE 'var ENEMY_KINDS = \[[^]]*\]' game/Rules.js | grep -oE '"[a-z_]+"' | tr -d '"') boss_daemon boss_guardian; do
  [ -f "assets/sprites/${enemy}_idle_a.txt" ] || missing="$missing ${enemy}_idle_a"
done
cd assets/sprites

if [ -n "$missing" ]; then
  echo "sprites the code asks for but nobody drew:$missing" >&2
  status=1
fi

listed=$(jq -r '.[]' index.json | sort)
present=$(for f in *.txt; do basename "$f" .txt; done | sort)

if ! diff <(echo "$listed") <(echo "$present") >/dev/null; then
  echo "index.json does not match the directory:" >&2
  diff <(echo "$listed") <(echo "$present") >&2 || true
  status=1
fi

[ "$status" -eq 0 ] && echo "sprites ok ($(echo "$present" | wc -l) grids)"
exit "$status"
