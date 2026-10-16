#!/bin/zsh
# MacMonitor'ü Apple Silicon + Intel için derler ve paylaşılabilir bir .dmg kurulum dosyası üretir.
# Çıktı: ~/Desktop/MacMonitor/dist/MacMonitor-<sürüm>.dmg
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=$(grep -A0 'CFBundleShortVersionString' build.sh | sed -E 's/.*<string>([^<]+)<\/string>.*/\1/')
SIGN_ID="MacMonitor Local"
# iCloud'la eşitlenen Masaüstü dosyalara Finder etiketleri ekleyip imzayı bozuyor: geçici klasörde çalış
WORK="${TMPDIR:-/tmp}/macmonitor-dmg"
APP="$WORK/stage/MacMonitor.app"
rm -rf "$WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "› Derleniyor (Apple Silicon + Intel)…"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos13.0 Sources/*.swift -o "$WORK/MacMonitor-arm64"
swiftc -O -parse-as-library -swift-version 5 -target x86_64-apple-macos13.0 Sources/*.swift -o "$WORK/MacMonitor-x86_64"
lipo -create "$WORK/MacMonitor-arm64" "$WORK/MacMonitor-x86_64" -output "$APP/Contents/MacOS/MacMonitor"

echo "› İkon ve paket…"
swift tools/make_icon.swift assets/logo.png "$WORK/icon_1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# build.sh'deki Info.plist'i aynen kullan (tek kaynak)
sed -n "/cat > \"\$APP\/Contents\/Info.plist\" <<'EOF'/,/^EOF/p" build.sh | sed '1d;$d' > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "› İmzalanıyor…"
xattr -cr "$APP"
tools/make_cert.sh "$SIGN_ID"
codesign --force --sign "$SIGN_ID" "$APP"

echo "› Kurulum penceresi hazırlanıyor…"
ln -s /Applications "$WORK/stage/Applications"
mkdir -p "$WORK/stage/.background"
swift tools/dmg_background.swift "$WORK/stage/.background/background.png"

RW="$WORK/rw.dmg"
hdiutil create -quiet -srcfolder "$WORK/stage" -volname "MacMonitor" -fs HFS+ -format UDRW -size 60m "$RW"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\// {print $NF}')

# Finder penceresi düzeni: simge görünümü, arka plan, simge konumları
# (Terminal'in Finder'ı kontrol etmesine izin istenebilir; reddedilirse düz bir .dmg üretilir)
osascript <<EOF || echo "  (Pencere düzeni atlandı — .dmg yine çalışır)"
tell application "Finder"
    tell disk "MacMonitor"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.png"
        set position of item "MacMonitor.app" of container window to {160, 190}
        set position of item "Applications" of container window to {480, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
sync
hdiutil detach -quiet "$MOUNT"

mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/MacMonitor-$VERSION.dmg"
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -rf "$WORK"
echo "✓ Hazır: $OUT"
lipo -archs "$APP" 2>/dev/null || true
