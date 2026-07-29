#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="${TMPDIR:-/tmp}/feitian-comparison-tests"

xcrun swiftc \
  -o "$TEST_BINARY" \
  "$ROOT/Sources/FeitianReport/ComparisonLogic.swift" \
  "$ROOT/Tests/ComparisonLogicTests.swift"

"$TEST_BINARY"
zsh "$ROOT/Tests/MetricCopyTest.sh"
zsh "$ROOT/Tests/MetricComparisonVisibilityTest.sh"
