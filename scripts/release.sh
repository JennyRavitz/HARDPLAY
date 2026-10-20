#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
zsh scripts/build.sh
app="$PWD/build/HARDPLAY.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
arch=$(uname -m)
release="$PWD/build/release"
staging="$PWD/build/dmg-staging"
mkdir -p "$release" "$staging"
ditto "$app" "$staging/HARDPLAY.app"
ln -sfn /Applications "$staging/Applications"
cp docs/INSTALL.ru.md "$staging/INSTALL.ru.md"
name="HARDPLAY-${version}-macOS-${arch}"
ditto -c -k --sequesterRsrc --keepParent "$app" "$release/$name.zip"
hdiutil create -volname "HARDPLAY $version" -srcfolder "$staging" -ov -format UDZO "$release/$name.dmg"
(cd "$release" && shasum -a 256 "$name.zip" "$name.dmg" > "$name.sha256")
codesign --verify --deep --strict "$app"
print "Release artifacts: $release/$name.{dmg,zip,sha256}"
