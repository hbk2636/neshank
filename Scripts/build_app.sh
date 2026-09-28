#!/bin/zsh
# ساخت کامل برنامهٔ «نشانک»، تبدیل به .app، و بسته‌بندی DMG روی دسکتاپ
# استفاده: Scripts/build_app.sh [debug|release]
set -e

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="NeshankYar"        # نام فایل اجرایی (CFBundleExecutable)
BUNDLE_NAME="نشانک"          # نام نمایشی و نام فایل .app
VERSION="1.0"
AUTHOR="hosein shahraki"
OUT_DIR="build"
APP="$OUT_DIR/$BUNDLE_NAME.app"
DESKTOP="${HOME}/Desktop"
DMG_NAME="نشانک-$VERSION.dmg"
DMG="$PWD/$DMG_NAME"            # نسخهٔ اصلی: پوشهٔ پروژه
DMG_DESKTOP="$DESKTOP/$DMG_NAME"

echo "==> ۱) کامپایل ($CONFIG)"
if [[ "$CONFIG" == "release" ]]; then
    swift build -c release
    BIN=".build/release/$APP_NAME"
else
    swift build
    BIN=".build/debug/$APP_NAME"
fi

echo "==> ۲) ساخت پوشهٔ بسته"
# بستهٔ قدیمی (با هر نامی) پاک می‌شود
rm -rf "$OUT_DIR"/*.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# باندل منابع SwiftPM (کتابخانهٔ نقشهٔ ذهنی و …) داخل منابع اپ
RESOURCE_BUNDLE=".build/${CONFIG}/NeshankYar_NeshankYar.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    rm -rf "$APP/Contents/Resources/NeshankYar_NeshankYar.bundle"
    ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/NeshankYar_NeshankYar.bundle"
    echo "    باندل منابع کپی شد"
fi

echo "==> ۳) ساخت آیکون (PNG + ICNS) از لوگوی پروژه"
mkdir -p "$OUT_DIR"
swift Scripts/make_icon.swift "$OUT_DIR/AppIcon-1024.png" "$APP/Contents/Resources/AppIcon.icns" "Resources/logo.png" > /dev/null
echo "    آیکون ساخته شد"

echo "==> ۴) امضای محلی (ad-hoc)"
# فایل‌های AppleDouble/.DS_Store (بازماندهٔ درایو FAT/exFAT) امضای کد را می‌شکنند — پیش از امضا پاک می‌شوند
find "$APP" \( -name "._*" -o -name ".DS_Store" \) -delete
codesign --force --sign - "$APP"
echo "    سازنده: $AUTHOR"

echo "==> ۵) ساخت DMG (پوشهٔ پروژه + دسکتاپ)"
STAGE="$OUT_DIR/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$BUNDLE_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$DMG_DESKTOP"
hdiutil create -volname "نشانک $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"
# نسخه‌ای هم روی دسکتاپ
cp -f "$DMG" "$DMG_DESKTOP"

echo "==> تمام شد:"
echo "    برنامه: $APP"
echo "    DMG:    $DMG"
echo "    DMG:    $DMG_DESKTOP"
echo "    اجرا:   open \"$APP\""
