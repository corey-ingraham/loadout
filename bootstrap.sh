#!/usr/bin/env bash
# =============================================================================
# loadout — bootstrap.sh
# One-shot entrypoint for a brand-new box. Clones the repo (if not already
# inside it) and dispatches to the CLI or GUI installer.
#
#   # Read it first (recommended), then run:
#   curl -fsSL https://raw.githubusercontent.com/<you>/loadout/main/bootstrap.sh -o loadout.sh
#   less loadout.sh
#   bash loadout.sh --all                 # CLI install
#   bash loadout.sh --gui-installer --all # GUI install
#
#   # Or clone and run directly:
#   git clone https://github.com/<you>/loadout && cd loadout
#   sudo ./install-cli.sh --all
#
# Passing --gui-installer routes to install-gui.sh; all other args pass through.
# AUTHORIZED USE ONLY — see install-cli.sh header.
# =============================================================================
set -euo pipefail

REPO_URL="${LOADOUT_REPO_URL:-https://github.com/corey-ingraham/loadout.git}"
REF="${LOADOUT_REF:-main}"
DEST="${LOADOUT_DEST:-$HOME/loadout}"
INSTALLER="install-cli.sh"

# Pull --gui-installer out of the argument list; forward the rest.
ARGS=()
for a in "$@"; do
    case "$a" in
        --gui-installer|--gui-install) INSTALLER="install-gui.sh" ;;
        *) ARGS+=("$a") ;;
    esac
done

# If we're already inside a checkout, just run in place.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/$INSTALLER" ] && [ -f "$HERE/lib/common.sh" ]; then
    exec bash "$HERE/$INSTALLER" "${ARGS[@]}"
fi

# Otherwise fetch the repo, then run.
if ! command -v git >/dev/null 2>&1; then
    echo "[*] Installing git ..."
    if command -v sudo >/dev/null 2>&1; then SUDO=sudo; else SUDO=""; fi
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git \
        || { echo "[FAIL] Could not install git." >&2; exit 1; }
fi

if [ -d "$DEST/.git" ]; then
    echo "[*] Updating existing checkout at $DEST ..."
    git -C "$DEST" pull --ff-only || true
else
    echo "[*] Cloning $REPO_URL -> $DEST ..."
    git clone --branch "$REF" --depth 1 "$REPO_URL" "$DEST"
fi

exec bash "$DEST/$INSTALLER" "${ARGS[@]}"
