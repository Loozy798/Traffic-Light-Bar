#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="${TMPDIR:-/tmp}/traffic-light-bar-tests"
mkdir -p "$TEST_DIR"
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" \
  "$ROOT_DIR/Traffic Light Bar/SystemStats.swift" \
  "$ROOT_DIR/Traffic Light Bar/MetricsMath.swift" \
  "$ROOT_DIR/Traffic Light Bar/ProcessSnapshot.swift" \
  "$ROOT_DIR/Traffic Light Bar/NetworkCounterReader.swift" \
  "$ROOT_DIR/Traffic Light Bar/TrendSeries.swift" \
  "$ROOT_DIR/Tests/MonitorTests.swift" -o "$TEST_DIR/monitor-tests"
"$TEST_DIR/monitor-tests"
