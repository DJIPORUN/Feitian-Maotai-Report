#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Sources/FeitianReport/App.swift"
grep -F 'Text("\(comparisonMode.rawValue)：\(comparison.summary)")' "$SOURCE" >/dev/null
grep -F 'comparisonMode: comparisonMode,' "$SOURCE" >/dev/null
grep -F 'comparisonIndex: comparisonIndex' "$SOURCE" >/dev/null
echo "PASS: MetricComparisonVisibilityTest"
