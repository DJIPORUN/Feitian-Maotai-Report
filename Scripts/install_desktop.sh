#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$("$ROOT/Scripts/build_app.sh")"
TARGET="$HOME/Desktop/飞天茅台实时报表.app"

pkill -f '/飞天茅台实时报表.app/Contents/MacOS/FeitianReport' 2>/dev/null || true
rm -rf "$TARGET"
cp -R "$SOURCE_APP" "$TARGET"
open "$TARGET"
echo "$TARGET"
