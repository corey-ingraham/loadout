#!/usr/bin/env bash
# =============================================================================
# loadout — install-gui.sh
# GUI superset: everything install-cli.sh does, plus desktop RE/SDR/pentest
# tools (Ghidra, Cutter, ImHex, SDR++, gqrx, URH, Burp, Wireshark GUI,
# virt-manager, ...). Run on a box that has (or will have) a desktop session.
#
#   sudo ./install-gui.sh --all           # all CLI + all GUI categories
#   sudo ./install-gui.sh --gui           # base + all GUI categories only
#   sudo ./install-gui.sh --gui_re --gui_sdr
#   ./install-gui.sh --all --dry-run
#   ./install-gui.sh                       # interactive menu (CLI + GUI)
#
# AUTHORIZED USE ONLY — see install-cli.sh header.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reuse the entire CLI framework + orchestration; sourcing does NOT auto-run
# main() (it's guarded by a BASH_SOURCE check in install-cli.sh).
RUN_MODE="gui"
# shellcheck source=install-cli.sh
. "$HERE/install-cli.sh"

# Warn (don't block) if there's clearly no graphical stack — GUI apps still
# install fine headless, but the user probably wants a desktop to run them.
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    warn "No DISPLAY/WAYLAND_DISPLAY detected — GUI apps will install but need a desktop to launch."
fi

main "$@"
