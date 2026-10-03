#!/bin/zsh
# ساخت کامل برنامهٔ «نشانک»، تبدیل به .app، و بسته‌بندی DMG روی دسکتاپ
# استفاده: Scripts/build_app.sh [debug|release]
set -e

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="NeshankYar"        # نام فایل اجرایی (CFBundleExecutable)
BUNDLE_NAME="نشانک"          # نام نمایشی و نام فایل .app
VERSION="1.7"
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

echo "==> ۳.۵) باندل yt-dlp (ابزار دانلود ویدیو)"
YTDLP_VER="2026.08.19"
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VER}/yt-dlp_macos"
if curl -fsSL --max-time 300 -o "$OUT_DIR/yt-dlp" "$YTDLP_URL"; then
    curl -fsSL --max-time 60 -o "$OUT_DIR/SHA2-256SUMS" \
        "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VER}/SHA2-256SUMS" || true
    if [[ -s "$OUT_DIR/SHA2-256SUMS" ]]; then
        expected=$(awk '$2=="yt-dlp_macos" || $2=="*yt-dlp_macos" {print $1}' "$OUT_DIR/SHA2-256SUMS" | head -1)
        actual=$(shasum -a 256 "$OUT_DIR/yt-dlp" | awk '{print $1}')
        if [[ -n "$expected" && "$expected" != "$actual" ]]; then
            echo "    خطا: SHA256 باینری yt-dlp با فایل رسمی نمی‌خواند"
            exit 1
        fi
    fi
    cp "$OUT_DIR/yt-dlp" "$APP/Contents/MacOS/yt-dlp"
    chmod +x "$APP/Contents/MacOS/yt-dlp"
    codesign --force --sign - "$APP/Contents/MacOS/yt-dlp" 2>/dev/null || true
    echo "    yt-dlp ${YTDLP_VER} باندل شد"
else
    echo "    خطا: دانلود yt-dlp ناموفق بود — اینترنت را بررسی کنید"
    exit 1
fi

# ffmpeg بومی arm64 (اختیاری): ادغام ویدیو+صدا و کیفیت بالاتر — نبودش فقط کیفیت را محدود می‌کند
# اولویت با بیلد استاتیک arm64 است (~۴۵ مگ، بدون نیاز به Rosetta و مصرف CPU کمتر)؛
# در صورت شکست، نسخهٔ evermeet (x86_64، نیازمند Rosetta) استفاده می‌شود.
FFMPEG_ARM64_URL="https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-darwin-arm64"
FFMPEG_URL="https://evermeet.cx/ffmpeg/getrelease/zip"
FFMPEG_OK=""
if curl -fsSL --max-time 300 -o "$OUT_DIR/ffmpeg-arm64" "$FFMPEG_ARM64_URL"; then
    if [[ "$(uname -m)" == "arm64" ]] && "$OUT_DIR/ffmpeg-arm64" -version >/dev/null 2>&1; then
        cp "$OUT_DIR/ffmpeg-arm64" "$APP/Contents/MacOS/ffmpeg"
        chmod +x "$APP/Contents/MacOS/ffmpeg"
        codesign --force --sign - "$APP/Contents/MacOS/ffmpeg" 2>/dev/null || true
        echo "    ffmpeg بومی arm64 باندل شد (ادغام و کیفیت بالاتر فعال)"
        FFMPEG_OK=1
    else
        echo "    هشدار: باینری arm64 اجرا نشد — تلاش با نسخهٔ جایگزین"
    fi
fi
if [[ -z "$FFMPEG_OK" ]]; then
    if curl -fsSL --max-time 300 -o "$OUT_DIR/ffmpeg.zip" "$FFMPEG_URL"; then
        if unzip -o -j "$OUT_DIR/ffmpeg.zip" "ffmpeg" -d "$APP/Contents/MacOS/" >/dev/null 2>&1; then
            chmod +x "$APP/Contents/MacOS/ffmpeg"
            codesign --force --sign - "$APP/Contents/MacOS/ffmpeg" 2>/dev/null || true
            echo "    ffmpeg باندل شد (ادغام و کیفیت بالاتر فعال)"
            FFMPEG_OK=1
        else
            echo "    هشدار: ffmpeg استخراج نشد — دانلود ویدیو محدود به تک‌فایلی‌ها"
        fi
    else
        echo "    هشدار: ffmpeg دانلود نشد — دانلود ویدیو محدود به تک‌فایلی‌ها"
    fi
fi

echo "==> ۳.۶) باندل deno + پلاگین PO Token (برای دانلود یوتیوب)"
DENO_ARCH="deno-x86_64-apple-darwin"; [[ "$(uname -m)" == "arm64" ]] && DENO_ARCH="deno-aarch64-apple-darwin"
if curl -fsSL --max-time 600 -o "$OUT_DIR/deno.zip" "https://github.com/denoland/deno/releases/latest/download/${DENO_ARCH}.zip"; then
    unzip -o -j "$OUT_DIR/deno.zip" deno -d "$APP/Contents/MacOS/" >/dev/null && chmod +x "$APP/Contents/MacOS/deno" && echo "    deno باندل شد"
else
    echo "    هشدار: deno باندل نشد — دانلود یوتیوب محدود می‌شود"
fi
# پلاگین bgutil PO Token Provider (پلاگین پایتونی + سرور اسکریپتی Node)
rm -rf /tmp/bgutil-vendor
if git clone --depth 1 https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git /tmp/bgutil-vendor 2>/dev/null; then
    # نصب کامل (tsc به typescript نیاز دارد) → کامپایل → حذف devDeps برای باندل
    (cd /tmp/bgutil-vendor/server && npm install --no-audit --no-fund >/dev/null 2>&1 && npx tsc >/dev/null 2>&1 && npm prune --omit=dev >/dev/null 2>&1) || true
    if [[ -f /tmp/bgutil-vendor/server/build/generate_once.js ]]; then
        mkdir -p "$APP/Contents/Resources/yt-dlp-plugins"
        rm -rf "$APP/Contents/Resources/yt-dlp-plugins/bgutil"
        cp -R /tmp/bgutil-vendor/plugin "$APP/Contents/Resources/yt-dlp-plugins/bgutil"
        rm -rf "$APP/Contents/Resources/bgutil-server"
        mkdir -p "$APP/Contents/Resources/bgutil-server"
        cp -R /tmp/bgutil-vendor/server/build "$APP/Contents/Resources/bgutil-server/build"
        cp /tmp/bgutil-vendor/server/package.json "$APP/Contents/Resources/bgutil-server/package.json"
        # -L: symlinkهای .bin روی درایو exFAT ساخته نمی‌شوند
        cp -RL /tmp/bgutil-vendor/server/node_modules "$APP/Contents/Resources/bgutil-server/node_modules"
        # AppleDouble روی exFAT: پیش از هرس پاک می‌شوند تا find خطای کاذب ندهد
        find "$APP/Contents/Resources/bgutil-server" "$APP/Contents/Resources/yt-dlp-plugins" \
            \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
        # هرس فایل‌های غیراجرایی node_modules (سورس‌مپ، تایپ‌ها، مستندات، کش بیلد):
        # در اجرا لازم نیستند ولی روی exFAT هر فایل کوچک یک کلاستر کامل (~۱۲۸K) می‌گیرد.
        find "$APP/Contents/Resources/bgutil-server/node_modules" \
            \( -name "*.map" -o -name "*.md" -o -name "*.d.ts" -o -name "*.d.mts" -o -name "*.d.cts" \
               -o -name "*.tsbuildinfo" -o -name ".eslintrc*" -o -name "*.tgz" \) -delete 2>/dev/null || true
        find "$APP/Contents/Resources/bgutil-server/node_modules" -type d \
            \( -name "__tests__" -o -name "test" \) -prune -exec rm -rf {} + 2>/dev/null || true
        # سورس‌مپ‌های بیلد کامپایل‌شده هم در اجرا لازم نیستند
        find "$APP/Contents/Resources/bgutil-server/build" -name "*.map" -delete 2>/dev/null || true
        echo "    پلاگین PO Token باندل شد (هرس‌شده)"
    else
        echo "    هشدار: کامپایل bgutil ناموفق — دانلود یوتیوب محدود می‌شود"
    fi
else
    echo "    هشدار: باندل PO Token ناموفق — دانلود یوتیوب محدود می‌شود"
fi

echo "==> ۴) امضای محلی (ad-hoc)"
# فایل‌های AppleDouble/.DS_Store (بازماندهٔ درایو FAT/exFAT) امضای کد را می‌شکنند — پیش از امضا پاک می‌شوند
find "$APP" \( -name "._*" -o -name ".DS_Store" \) -delete
codesign --force --sign - "$APP"
echo "    سازنده: $AUTHOR"

echo "==> ۵) ساخت DMG (پوشهٔ پروژه + دسکتاپ)"
# استیج روی دیسک داخلی (APFS): اگر استیج روی درایو exFAT باشد،
# hdiutil فایل‌سیستم exFAT داخل DMG می‌گذارد و حجم چند برابر می‌شود.
STAGE_BASE="$(mktemp -d /tmp/neshank-dmg-XXXXXX)"
STAGE="$STAGE_BASE/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$BUNDLE_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$DMG_DESKTOP"
hdiutil create -volname "نشانک $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE_BASE"
# نسخه‌ای هم روی دسکتاپ
cp -f "$DMG" "$DMG_DESKTOP"

echo "==> تمام شد:"
echo "    برنامه: $APP"
echo "    DMG:    $DMG"
echo "    DMG:    $DMG_DESKTOP"
echo "    اجرا:   open \"$APP\""
