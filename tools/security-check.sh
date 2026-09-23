#!/usr/bin/env bash
# The release checklist from 05-seguranca-publicacao.md, as a command.
#
# Every item here is something a reviewer would look for in a plugin that runs
# unsandboxed inside someone's shell. Running it is cheaper than remembering
# it, and it belongs in the repository so the next change has to pass it too.
set -uo pipefail

cd "$(dirname "$0")/.."

status=0
code=(*.qml components/*.qml game/*.js)

fail() { echo "  FAIL  $1" >&2; status=1; }
pass() { echo "  ok    $1"; }

# Comments are stripped first: this file is full of sentences explaining why
# the plugin does not do these things, and a checklist that trips over its own
# documentation is a checklist people learn to ignore.
strip_comments() {
  sed -E 's,([^:])//.*,\1,; s,^[[:space:]]*//.*,,' "$@"
}

check_absent() {
  local label=$1 pattern=$2
  local hits=""
  local file
  for file in "${code[@]}"; do
    local found
    found=$(strip_comments "$file" | grep -nE "$pattern" | sed "s|^|$file:|" || true)
    [ -n "$found" ] && hits="$hits$found"$'\n'
  done
  hits=$(printf '%s' "$hits" | sed '/^$/d')
  if [ -n "$hits" ]; then
    fail "$label"
    printf '%s\n' "$hits" | sed 's/^/        /' >&2
  else
    pass "$label"
  fi
}

echo "Omaquest security checklist"
echo

check_absent "no shell invocation"        '\bbash[[:space:]]+-[lc]|\bsh[[:space:]]+-c|/bin/sh'
check_absent "no network"                 'XMLHttpRequest|\bcurl\b|\bwget\b|checkupdates|WebSocket|\.open\("GET|Qt\.openUrlExternally'
check_absent "no privilege escalation"    '\bsudo\b|\bpkexec\b|\bdoas\b'
check_absent "no window titles or media metadata" 'toplevel\.title|activeToplevel\.title|lastIpcObject|trackTitle|trackArtist|\.metadata|windowTitle'
check_absent "no notify-send"             'notify-send'
check_absent "no rich text in the panel"  'textFormat:[[:space:]]*Text\.(RichText|StyledText|AutoText)'
check_absent "no eval"                    '\beval\(|new[[:space:]]+Function\('

# Files are written through exactly three named FileViews. Any other setText
# is a write nobody declared, and this is where it gets caught — it already
# has, twice.
writers="saveFile chronicleFile bardBriefFile"
writer_pattern=$(echo "$writers" | tr ' ' '|')

stray_writes=$(grep -rnoE '[A-Za-z_]+\.setText\(' "${code[@]}" 2>/dev/null \
  | grep -vE "($writer_pattern)\.setText" || true)
if [ -n "$stray_writes" ]; then
  fail "files are written only through $writers"
  printf '%s\n' "$stray_writes" | sed 's/^/        /' >&2
else
  pass "files are written only through $writers"
fi

# And every one of them points inside the state directory. A declared writer
# aimed somewhere else is worse than an undeclared one.
paths_ok=1
for pair in "savePath:stateDir" "chroniclePath:stateDir" "bardBriefPath:bardDir"; do
  prop=${pair%%:*}
  root_dir=${pair##*:}
  grep -qE "readonly property string $prop: $root_dir" Service.qml || paths_ok=0
done
grep -qE 'readonly property string bardDir: stateDir' Service.qml || paths_ok=0

if [ "$paths_ok" -eq 1 ]; then
  pass "every writer points inside the state directory"
else
  fail "every writer points inside the state directory"
fi

# Every detached command starts with a program this README lists.
allowed='mkdir|root\.notifyBin|"omarchy"|"pw-play"'
detached=$(grep -rn -A1 'execDetached(\[' "${code[@]}" 2>/dev/null \
  | grep -vE 'execDetached\(\[$|^--' | grep -E '^\S+:[0-9]+[:-]' \
  | grep -vE "execDetached\\(\\[\"?($allowed)" | grep -vE "^[^:]+:[0-9]+-[[:space:]]*(\"?($allowed))" || true)
if [ -n "$detached" ]; then
  fail "every detached command is one the README lists"
  printf '%s\n' "$detached" | sed 's/^/        /' >&2
else
  pass "every detached command is one the README lists"
fi

# Every Process command is a literal array.
bad_process=$(grep -rn -A2 'Process {' "${code[@]}" 2>/dev/null \
  | grep -E 'command:' | grep -vE 'command: \[' || true)
if [ -n "$bad_process" ]; then
  fail "every Process command is a literal array"
  printf '%s\n' "$bad_process" | sed 's/^/        /' >&2
else
  pass "every Process command is a literal array"
fi

# No symlinks: the Omarchy validator rejects them.
links=$(find . -type l -not -path './.git/*' 2>/dev/null || true)
[ -z "$links" ] && pass "no symlinks" || { fail "no symlinks"; printf '%s\n' "$links" | sed 's/^/        /' >&2; }

# Nothing binary except the previews and the generated audio. Audio is
# allowed because it is **generated**, not recorded: tools/make-sounds.py is
# its source, the way the sprite grids are their own. A .wav that appeared
# without the script producing it is exactly what this is here to catch.
binaries=$(find . -type f -not -path './.git/*' -not -name '*.png' -not -name '*.wav' \
  -exec file --mime-type {} \; 2>/dev/null \
  | grep -vE 'text/|inode/|application/json' || true)
[ -z "$binaries" ] && pass "no binaries but the previews and the generated audio" \
  || { fail "no binaries but the previews and the generated audio"; printf '%s\n' "$binaries" | sed 's/^/        /' >&2; }

# Every sound in the tree has to be one the generator makes, and running the
# generator has to reproduce it byte for byte. Otherwise "generated from code"
# is a claim rather than a fact.
if command -v python3 >/dev/null 2>&1; then
  before=$(find assets/sounds -name '*.wav' -exec sha256sum {} \; 2>/dev/null | sort)
  python3 tools/make-sounds.py >/dev/null 2>&1
  after=$(find assets/sounds -name '*.wav' -exec sha256sum {} \; 2>/dev/null | sort)
  if [ "$before" = "$after" ]; then
    pass "every sound is reproduced exactly by tools/make-sounds.py"
  else
    fail "a sound in the tree is not what the generator produces"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^/        /' >&2 || true
  fi
else
  echo "  skip  sound reproducibility (no python3)"
fi

# The three opt-ins are off in the manifest.
for key in sensorAgents sensorGit bardEnabled; do
  value=$(jq -r --arg k "$key" '.barWidget.defaults[$k]' manifest.json)
  schema=$(jq -r --arg k "$key" '.barWidget.schema[] | select(.key == $k) | .defaultValue' manifest.json)
  if [ "$value" = "false" ] && [ "$schema" = "false" ]; then
    pass "$key defaults to off, in defaults and in schema"
  else
    fail "$key defaults to off (defaults=$value schema=$schema)"
  fi
done

# The manifest version matches the newest changelog heading.
manifest_version=$(jq -r .version manifest.json)
changelog_version=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | tr -d '## []')
if [ "$manifest_version" = "$changelog_version" ]; then
  pass "manifest version $manifest_version matches the changelog"
else
  fail "manifest says $manifest_version, changelog says ${changelog_version:-nothing}"
fi

echo
[ "$status" -eq 0 ] && echo "checklist clean" || echo "checklist FAILED" >&2
exit "$status"
