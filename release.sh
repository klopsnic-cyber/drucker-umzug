#!/bin/bash
# Release: Tests, Build, SHA256 schreiben, committen, GitHub-Release, dann pushen. VERSION vorher erhöhen.
# Der Updater liest VERSION und SHA256 auf main, deshalb erst Release anlegen, dann pushen.
set -euo pipefail
cd "$(dirname "$0")"
V=$(cat VERSION)
/bin/bash tests/run-tests.sh >/dev/null
./build.sh
shasum -a 256 dist/Drucker-Umzug.zip | cut -d' ' -f1 > SHA256
git add VERSION SHA256 CHANGELOG.md
git diff --cached --quiet || git commit -m "Release $V"
gh release create "v$V" dist/Drucker-Umzug.zip --title "Drucker-Umzug $V" --notes "Siehe CHANGELOG.md"
git push
