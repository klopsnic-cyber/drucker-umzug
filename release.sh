#!/bin/bash
# Release: Tests, Build, GitHub-Release mit Drucker-Umzug.zip. VERSION vorher erhöhen und committen.
# Der Updater liest VERSION auf main, deshalb erst Release anlegen, dann pushen.
set -euo pipefail
cd "$(dirname "$0")"
V=$(cat VERSION)
/bin/bash tests/run-tests.sh >/dev/null
./build.sh
gh release create "v$V" dist/Drucker-Umzug.zip --title "Drucker-Umzug $V" --notes "Siehe CHANGELOG.md"
git push
