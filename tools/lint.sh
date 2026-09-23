#!/usr/bin/env bash
# qmllint over every QML file in the plugin, resolved against the installed
# shell so `qs.Commons` and `qs.Ui` are the real ones.
#
# Two things need arranging first.
#
# qmllint resolves `import qs.Commons` by looking for qs/Commons/qmldir on an
# import path. The shell ships those qmldir files but not the `qs` root that
# the Quickshell runtime synthesizes, so one gets built here out of a symlink
# — in a scratch directory rather than in the repository, because
# `omarchy plugin validate` rejects a plugin folder that contains symlinks.
#
# And qmllint is not on PATH on Omarchy even though qt6-declarative ships it,
# so look it up in Qt's own bindir before giving up.
set -euo pipefail

cd "$(dirname "$0")/.."

shell_path="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
if [ ! -d "$shell_path" ]; then
  echo "lint: shell source not found at $shell_path (set OMARCHY_PATH)" >&2
  exit 1
fi

qmllint=$(command -v qmllint || true)
if [ -z "$qmllint" ]; then
  for candidate in /usr/lib/qt6/bin/qmllint /usr/lib/qt/bin/qmllint; do
    [ -x "$candidate" ] && qmllint="$candidate" && break
  done
fi

if [ -z "$qmllint" ]; then
  echo "lint: qmllint not found (install qt6-declarative)" >&2
  exit 1
fi

qmlroot=$(mktemp -d)
trap 'rm -rf "$qmlroot"' EXIT
ln -sfn "$shell_path" "$qmlroot/qs"

mapfile -t files < <(find . -name '*.qml' -not -path './.git/*' | sort)
if [ "${#files[@]}" -eq 0 ]; then
  echo "lint: no QML files" >&2
  exit 1
fi

# Quickshell's Process and Socket declare signal parameters whose C++ types
# (QProcess::ExitStatus, QLocalSocket::LocalSocketError) are not exported to
# QML, so qmllint cannot resolve them no matter how the handler is written.
# Omarchy's own plugins carry the same warnings. Every other category stays on.
# qmllint exits 0 on warnings, so say what it actually found rather than
# printing "ok" over a wall of them. The facade the shell hands plugins is
# typed QtObject and Loader.item is QObject, so every `bar.foreground` and
# `panelLoader.item.open()` is a warning that cannot be written away — the
# shell's own clock plugin carries 68 of them. Errors are what fails a build.
out=$("$qmllint" --signal-handler-parameters disable \
  -I "$qmlroot" -I "$shell_path" -I . "${files[@]}" 2>&1) || status=$?
status=${status:-0}

[ -n "$out" ] && printf '%s\n' "$out"

if [ "$status" -ne 0 ]; then
  echo "qmllint: FAILED (${#files[@]} files)" >&2
  exit "$status"
fi

echo "qmllint: no errors (${#files[@]} files, $(printf '%s' "$out" | grep -c '^Warning:' || true) unresolvable-facade warnings)"
