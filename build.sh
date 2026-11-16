#!/bin/bash
# Baut dist/Drucker-Umzug.app und dist/Drucker-Umzug.zip (App + .command + README).
set -euo pipefail
cd "$(dirname "$0")"
V=$(cat VERSION)
rm -rf dist && mkdir -p dist/pkg
sed "s/__VERSION__/$V/" app/main.applescript > dist/main.applescript
osacompile -o dist/pkg/Drucker-Umzug.app dist/main.applescript
cp Drucker-Umzug.command dist/pkg/Drucker-Umzug.app/Contents/Resources/
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" dist/pkg/Drucker-Umzug.app/Contents/Info.plist 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $V" dist/pkg/Drucker-Umzug.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string de.infralatis.druckerumzug" dist/pkg/Drucker-Umzug.app/Contents/Info.plist 2>/dev/null || true
codesign --force --deep -s - dist/pkg/Drucker-Umzug.app   # ad-hoc, sonst meldet Apple Silicon "beschädigt"
cp Drucker-Umzug.command README.md dist/pkg/
ditto -c -k --sequesterRsrc dist/pkg dist/Drucker-Umzug.zip
echo "Gebaut: dist/Drucker-Umzug.zip (Version $V)"
