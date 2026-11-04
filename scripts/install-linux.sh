#!/usr/bin/env bash
# Installs the Linux build for this user, with a launcher icon.
# The in-game updater replaces the installed executable in place.
# Usage: scripts/install-linux.sh [path/to/ac130-gunner.x86_64]
set -euo pipefail
cd "$(dirname "$0")/.."

src="${1:-build/linux/ac130-gunner.x86_64}"
dest="$HOME/.local/share/ac130-gunner"
apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor/256x256/apps"

mkdir -p "$dest" "$apps" "$icons"
install -m 755 "$src" "$dest/ac130-gunner.x86_64"
rsvg-convert -w 256 -h 256 icon.svg -o "$icons/ac130-gunner.png"

cat > "$apps/ac130-gunner.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AC-130 Gunner
Comment=Gunship sensor operator game
Exec=$dest/ac130-gunner.x86_64
Path=$dest
Icon=ac130-gunner
Terminal=false
Categories=Game;ActionGame;
StartupWMClass=AC-130 Gunner
EOF

update-desktop-database "$apps" 2>/dev/null || true
echo "Installed to $dest"
