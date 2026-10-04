#!/bin/zsh
# Run the logic-layer tests + data-safety tests (backup / migration / node_count)
# XCTest is unavailable with bare Command Line Tools; like the rest of the project,
# we compile with swiftc in Swift 5 mode. App/ and Views/ are excluded because
# @main clashes with the test file's top-level code.
# Usage: Scripts/run_tests.sh
set -e
cd "$(dirname "$0")/.."

OUT=/tmp/neshank-test-bin
swiftc -swift-version 5 -o "$OUT" \
  Sources/NeshankYar/Models/*.swift \
  Sources/NeshankYar/Store/*.swift \
  Sources/NeshankYar/Services/*.swift \
  Sources/NeshankYar/Views/Designs/UIDesign.swift \
  Tests/NeshankTest/main.swift

"$OUT"
