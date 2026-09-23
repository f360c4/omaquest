#!/usr/bin/env bash
# What this plugin costs, in the two ways that can actually be measured.
#
# Measured, on a two-monitor desk with a dozen bar plugins, three paired
# four-minute windows each way:
#
#   with     8.45%   19.45%    5.42%   of a core
#   without  9.16%    9.93%   10.04%
#
#   memory   509 MB with, 517 MB without
#
# Read those honestly: the shell swings by more between windows than the
# plugin could possibly add, one pair came back *lower* with it enabled, and
# the memory delta is negative. Both instruments are saying the same thing —
# Omaquest is below the noise floor of the shell it runs inside. That is the
# answer to "is it light", and it is a better one than a fabricated decimal.
#
# What can be stated exactly is the work: every timer, how often, and what it
# does. That comes out of the source rather than out of a stopwatch, and the
# check below fails if a new timer ever runs faster than the budget allows.
#
#   tools/weight.sh            print the budget
#   tools/weight.sh --memory   also measure RSS with and against without
#                              (disables the plugin for a minute — ask first)
set -uo pipefail

cd "$(dirname "$0")/.."

echo "What runs, and how often"
echo

printf '  %-34s %s\n' "world tick" "every 60 s"
printf '  %-34s %s\n' "compositor burst debounce" "1 s, single-shot, only after an event"
printf '  %-34s %s\n' "theme change debounce" "2 s, single-shot, only after a change"
printf '  %-34s %s\n' "save debounce" "5 s, single-shot, at most one write per 5 s"
printf '  %-34s %s\n' "sprite frame" "110-1500 ms by animation; two property writes, no allocation"
printf '  %-34s %s\n' "coredumpctl" "every 15 min, one process"
printf '  %-34s %s\n' "agent tokens (opt-in, off)" "every 15 min"
printf '  %-34s %s\n' "git commits (opt-in, off)" "every 30 min"
echo
echo "  The only thing that runs faster than a second is the sprite's frame"
echo "  flip, which swaps which of two pre-built layers is visible and"
echo "  allocates nothing. It stops when the sprite is not on screen, and"
echo "  nothing at all runs before there is a hero."
echo

# Assert it, rather than only claiming it: any Timer in the plugin shorter than
# a second that is not one of the documented single-shot debounces is a
# regression, and this is where it gets caught.
echo "Timers in the source"
bad=0
while IFS= read -r line; do
  file=${line%%:*}
  interval=$(sed -E 's/.*interval:[[:space:]]*([0-9]+).*/\1/' <<<"$line")
  [[ $interval =~ ^[0-9]+$ ]] || continue
  repeat="one-shot"
  printf '  %-34s %s ms\n' "$(basename "$file")" "$interval"
  # The sprite's cadence is a binding rather than a literal, so anything
  # literal and under a second here is something new and wants explaining.
  if (( interval < 1000 )); then
    echo "      ^ a literal interval under a second: only a debounce may be" >&2
    bad=1
  fi
done < <(grep -rn "interval:[[:space:]]*[0-9]" --include=*.qml . | grep -v "^\./\.git")

echo
if (( bad )); then
  echo "FAILED: a timer runs faster than the budget allows" >&2
  exit 1
fi

# Every repeating Timer has to be gated on something, or it runs for a plugin
# with no hero in it.
echo "Repeating timers are gated on the game being up:"
grep -rn -A2 "repeat: true" --include=*.qml . | grep -c "running:" | xargs printf '  %s of them carry a running: condition\n'
echo

if [[ ${1:-} != "--memory" ]]; then
  echo "Run with --memory to measure RSS as well."
  exit 0
fi

pid() { pgrep -x quickshell | head -1; }
rss() { awk '/VmRSS/ {print $2}' "/proc/$1/status" 2>/dev/null; }

settle() { sleep 20; }

echo "Memory"
p=$(pid); [ -n "$p" ] || { echo "  the shell is not running" >&2; exit 1; }
settle
with=$(rss "$p")

omarchy plugin disable f360c4.omaquest >/dev/null 2>&1
settle
p=$(pid)
without=$(rss "$p")

omarchy plugin enable f360c4.omaquest >/dev/null 2>&1
omarchy bar move f360c4.omaquest --section right >/dev/null 2>&1

printf '  with:    %s kB\n' "$with"
printf '  without: %s kB\n' "$without"
printf '  delta:   %s kB\n' "$((with - without))"
echo
echo "  A shell restart moves this as much as the plugin does, so read it as an"
echo "  order of magnitude rather than a figure."
