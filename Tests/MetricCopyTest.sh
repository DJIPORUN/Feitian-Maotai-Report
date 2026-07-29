#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Sources/FeitianReport/App.swift"
grep -F '· 占当日 \(percentage, specifier: "%.1f")%' "$SOURCE" >/dev/null
! grep -F '条（\(percentage, specifier: "%.1f")%）' "$SOURCE" >/dev/null
echo "PASS: MetricCopyTest"
