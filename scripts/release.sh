#!/usr/bin/env bash
# Builds the Linux and Windows releases and publishes them on GitHub,
# where the in-game updater finds them.
# Usage: scripts/release.sh 0.1.1
# Write the release notes to release/notes-v0.1.1.md first.
set -euo pipefail
cd "$(dirname "$0")/.."

ver="${1:?version, e.g. 0.1.1}"
notes="release/notes-v$ver.md"
[[ -f $notes ]] || { echo "Write $notes first." >&2; exit 1; }
[[ -z $(git status --porcelain --untracked-files=no) ]] || { echo "Commit your changes first." >&2; exit 1; }

sed -i "s/^config\/version=.*/config\/version=\"$ver\"/" project.godot
mkdir -p build/linux build/windows release
godot --headless --path . --export-release "Linux" build/linux/ac130-gunner.x86_64
godot --headless --path . --export-release "Windows" build/windows/ac130-gunner.exe

rm -f release/ac130-gunner-*-x86_64.zip
(cd build/linux && zip -9 -q ../../release/ac130-gunner-linux-x86_64.zip ac130-gunner.x86_64)
(cd build/windows && zip -9 -q ../../release/ac130-gunner-windows-x86_64.zip ac130-gunner.exe)

git add project.godot
git commit -q -m "Release v$ver" || true
git tag "v$ver"
git push -q origin HEAD --tags
gh release create "v$ver" release/ac130-gunner-linux-x86_64.zip release/ac130-gunner-windows-x86_64.zip \
	--title "AC-130 Gunner v$ver" --notes-file "$notes"
