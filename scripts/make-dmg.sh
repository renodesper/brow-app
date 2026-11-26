#!/bin/sh
# Wraps an app in a plain disk image: the app, and a shortcut to /Applications to drag it onto.
# Usage: scripts/make-dmg.sh build/Brow.app build/Brow-0.2.0.dmg
set -eu

app="${1:?path to the .app}"
dmg="${2:?path of the .dmg to make}"
name="$(basename "$app" .app)"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "$name" -srcfolder "$staging" -format UDZO -ov "$dmg" >/dev/null
echo "Made $dmg"
