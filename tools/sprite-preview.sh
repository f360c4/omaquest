#!/usr/bin/env bash
# Print a sprite in the terminal, so a silhouette can be judged without
# reloading the shell. Layers a second grid over the first when given one:
#
#   tools/sprite-preview.sh orc_idle_a
#   tools/sprite-preview.sh dwarf_idle_a warrior_gear_a
set -euo pipefail

cd "$(dirname "$0")/../assets/sprites"

[ $# -ge 1 ] || { echo "usage: $(basename "$0") <sprite> [overlay]" >&2; exit 1; }

render() {
  local name=$1
  [ -f "$name.txt" ] || { echo "no such sprite: $name" >&2; exit 1; }
  cat "$name.txt"
}

if [ $# -eq 1 ]; then
  render "$1" | sed 's/X/██/g; s/\./  /g'
else
  # Merge cell by cell: an X in either grid is an X in the result.
  paste -d'\n' <(render "$1") <(render "$2") \
    | awk 'NR%2{a=$0; next} {out=""; for (i=1; i<=length(a); i++)
        out = out ((substr(a,i,1)=="X" || substr($0,i,1)=="X") ? "██" : "  "); print out}'
fi
