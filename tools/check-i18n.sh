#!/usr/bin/env bash
# Every dictionary must carry exactly the keys en.json carries, and no empty
# values. A missing key degrades to English at runtime, which is the right
# behaviour for a user but the wrong thing to ship without noticing.
set -euo pipefail

cd "$(dirname "$0")/.."
cd i18n

base=$(jq -r 'keys[]' en.json | sort)
status=0

for file in *.json; do
  [ "$file" = "en.json" ] && continue

  if ! diff <(echo "$base") <(jq -r 'keys[]' "$file" | sort) >/dev/null; then
    echo "$file: keys differ from en.json" >&2
    diff <(echo "$base") <(jq -r 'keys[]' "$file" | sort) >&2 || true
    status=1
  fi

  if ! jq -e 'to_entries | all(.value | type == "string" and . != "")' "$file" >/dev/null; then
    echo "$file: empty or non-string value" >&2
    status=1
  fi
done

if ! jq -e 'to_entries | all(.value | type == "string" and . != "")' en.json >/dev/null; then
  echo "en.json: empty or non-string value" >&2
  status=1
fi

[ "$status" -eq 0 ] && echo "i18n ok"
exit "$status"
