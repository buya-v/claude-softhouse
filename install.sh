#!/usr/bin/env bash
# Install the Softhouse skills into a Claude Code skills directory.
#
#   ./install.sh                 # user-level: ~/.claude/skills/
#   ./install.sh /path/to/repo   # project-level: <repo>/.claude/skills/

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills"

if [ $# -ge 1 ]; then
  DEST="${1%/}/.claude/skills"
else
  DEST="$HOME/.claude/skills"
fi

if [ ! -d "$SRC" ]; then
  echo "error: skills/ not found next to install.sh" >&2
  exit 1
fi

mkdir -p "$DEST"

for skill in "$SRC"/*/; do
  name="$(basename "$skill")"
  if [ -e "$DEST/$name" ]; then
    echo "  replacing $name"
    rm -rf "${DEST:?}/$name"
  else
    echo "  installing $name"
  fi
  cp -r "$skill" "$DEST/$name"
done

echo
echo "Installed to $DEST"
echo "Start a Claude Code session and run: /softhouse-plan <requirement>"
