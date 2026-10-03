#!/bin/zsh
# اجرای تست‌های لایهٔ منطق + تست‌های ایمنی داده (بک‌آپ/مهاجرت/node_count)
# XCTest با CommandLineTools در دسترس نیست؛ مثل بقیهٔ پروژه با swiftc در حالت Swift 5 کامپایل می‌شود.
# فایل‌های App/ و Views/ حذف می‌شوند: @main با کد سطح‌بالای فایل تست تداخل دارد.
# استفاده: Scripts/run_tests.sh
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
