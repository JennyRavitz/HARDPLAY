#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/shared-cache" -debug-info-format none
APP="$PWD/build/HARDPLAY.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/out/Products/Release/HARDPLAY "$APP/Contents/MacOS/HARDPLAY.new"
mv -f "$APP/Contents/MacOS/HARDPLAY.new" "$APP/Contents/MacOS/HARDPLAY"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>HARDPLAY</string>
<key>CFBundleIdentifier</key><string>local.hardplay.player</string>
<key>CFBundleName</key><string>Hard Play</string>
<key>CFBundleDisplayName</key><string>Hard Play</string>
<key>CFBundleVersion</key><string>21</string>
<key>CFBundleShortVersionString</key><string>0.15.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>UTExportedTypeDeclarations</key><array><dict><key>UTTypeIdentifier</key><string>local.hardplay.playlist</string><key>UTTypeDescription</key><string>HARDPLAY Playlist</string><key>UTTypeConformsTo</key><array><string>public.json</string></array><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>hardplay</string></array><key>public.mime-type</key><string>application/vnd.hardplay.playlist+json</string></dict></dict></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>HARDPLAY Playlist</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Owner</string><key>LSItemContentTypes</key><array><string>local.hardplay.playlist</string></array></dict><dict><key>CFBundleTypeName</key><string>Audio</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array><string>public.audio</string></array></dict></array>
</dict></plist>
PLIST
cp assets/branding/hard-play-front-icon-v1.png "$APP/Contents/Resources/HardPlayButton.png"
cp assets/branding/hard-play-red-keycap-v1.png "$APP/Contents/Resources/RedKeycap.png"
sips -z 1024 1024 assets/branding/hard-play-front-icon-v1.png --out "$PWD/build/icon.png" >/dev/null
mkdir -p "$PWD/build/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PWD/build/icon.png" --out "$PWD/build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$PWD/build/icon.png" --out "$PWD/build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$PWD/build/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns" <<'PYICON'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
chunks = []
for code, name in [('icp4','icon_16x16.png'), ('icp5','icon_32x32.png'), ('icp6','icon_32x32@2x.png'), ('ic07','icon_128x128.png'), ('ic08','icon_256x256.png'), ('ic09','icon_512x512.png'), ('ic10','icon_512x512@2x.png')]:
    data = (root / name).read_bytes()
    chunks.append(code.encode() + struct.pack('>I',len(data)+8) + data)
payload = b''.join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b'icns' + struct.pack('>I',len(payload)+8) + payload)
PYICON
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/HARDPLAY" --self-test
"$APP/Contents/MacOS/HARDPLAY" --queue-test
print "Built: $APP"
