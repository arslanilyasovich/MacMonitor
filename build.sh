#!/bin/zsh
# MacMonitor'ü derler, .app paketini oluşturur, sabit sertifikayla imzalar ve /Applications'a kurar.
set -e
cd "$(dirname "$0")"

# Derleme iCloud dışında yapılır: Masaüstü iCloud'la eşitlendiği için dosyalara geri eklenen
# Finder etiketleri kod imzalamayı bozuyor.
BUILD="${TMPDIR:-/tmp}/macmonitor-build"
APP="$BUILD/MacMonitor.app"
SIGN_ID="MacMonitor Local"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos13.0 \
    Sources/*.swift -o "$APP/Contents/MacOS/MacMonitor"

# Uygulama ikonu: make_icon.swift 1024px çizer, iconutil tüm boyutları .icns'e paketler
swift tools/make_icon.swift assets/logo.png $BUILD/icon_1024.png
ICONSET=$BUILD/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s $BUILD/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) $BUILD/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacMonitor</string>
    <key>CFBundleDisplayName</key><string>Mac Monitör</string>
    <key>CFBundleIdentifier</key><string>local.a26.macmonitor</string>
    <key>CFBundleExecutable</key><string>MacMonitor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.3</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>prod. by Arslan · © 2026 Arslan</string>
    <key>NSAppleEventsUsageDescription</key><string>Çöp Kutusu'nu boşaltmak için Finder'a komut gönderir.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>İndirilenler klasöründeki büyük dosyaları bulmak için.</string>
    <key>NSDesktopFolderUsageDescription</key><string>Masaüstündeki büyük ve kopya dosyaları bulmak için.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Belgeler klasöründeki büyük ve kopya dosyaları bulmak için.</string>
</dict>
</plist>
EOF

xattr -cr "$APP"   # Masaüstü/iCloud'un eklediği Finder bilgileri imzalamayı bozar
# Sabit imza: macOS izinleri imzaya bağlıdır, böylece her derlemede yeniden sorulmaz
tools/make_cert.sh "$SIGN_ID"
codesign --force --sign "$SIGN_ID" "$APP"

pkill -x MacMonitor 2>/dev/null || true
rm -rf /Applications/MacMonitor.app
ditto "$APP" /Applications/MacMonitor.app

# Her girişte otomatik başlat (LaunchAgent). İlk kurulumda eklenir; sonra uygulamadaki ayar yönetir.
AGENT=~/Library/LaunchAgents/local.a26.macmonitor.plist
[ -f "$AGENT" ] || cat > "$AGENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.a26.macmonitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>/Applications/MacMonitor.app</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
plutil -lint "$AGENT"

open /Applications/MacMonitor.app
echo "Kuruldu: /Applications/MacMonitor.app"
