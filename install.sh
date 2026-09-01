#!/bin/bash
# Klipvault installer. Builds, installs to /Applications, and starts it.
#   ./install.sh              install (or upgrade in place)
#   ./install.sh --uninstall  remove the app; asks before touching your vault
set -euo pipefail
cd "$(dirname "$0")"

APP="Klipvault.app"
DEST="/Applications/$APP"
VAULT="$HOME/Library/Application Support/Klipvault"
bold() { printf '\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  pkill -f "$APP" 2>/dev/null || true
  rm -rf "$DEST"
  bold "Removed $DEST"
  if [ -d "$VAULT" ]; then
    echo
    echo "Your encrypted history is still at:"
    echo "  $VAULT"
    read -r -p "Delete it too? This cannot be undone. [y/N] " reply
    case "$reply" in [yY]*) rm -rf "$VAULT"; bold "Vault erased." ;; *) echo "Kept." ;; esac
  fi
  exit 0
fi

# --- checks -----------------------------------------------------------------
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || die "Klipvault needs macOS 14 or later (found $(sw_vers -productVersion))."

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
  bold "The Xcode Command Line Tools are needed to build Klipvault."
  echo "Starting the installer — rerun ./install.sh when it finishes."
  xcode-select --install 2>/dev/null || true
  exit 1
fi

# --- build ------------------------------------------------------------------
bold "Building Klipvault…"
./build.sh >/dev/null 2>&1 || { ./build.sh; die "Build failed — output above."; }

# --- install ----------------------------------------------------------------
if pgrep -f "$APP" >/dev/null 2>&1; then
  echo "Stopping the running copy…"
  pkill -f "$APP" || true
  sleep 1
fi

rm -rf "$DEST"
cp -R "$APP" "$DEST"
# Only matters if this folder arrived as a download; a local build is never quarantined.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"
sleep 1

# --- done -------------------------------------------------------------------
cat <<'DONE'

  Klipvault is installed and running in your menu bar.

  Press  ⌘⇧V  to open your clipboard history.

  Two optional next steps, both inside Preferences (⌘, from the menu):
    • Accessibility permission  — lets Klipvault press ⌘V for you.
      Without it, selecting an item still copies; you paste yourself.
    • Launch at login           — General tab, one checkbox.

  Your history is encrypted from the first copy. Nothing else to set up.

  Uninstall any time with:  ./install.sh --uninstall

DONE
