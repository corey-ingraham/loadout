#!/usr/bin/env bash
# =============================================================================
# loadout — install-cli.sh
# Headless installer for RE / firmware / SDR / pentest / cracking / cloning /
# net / virtualization / containers tooling on a Debian-family box (incl. Pi).
#
#   sudo ./install-cli.sh --all              # everything (CLI)
#   sudo ./install-cli.sh --re --sdr --net   # pick categories
#   ./install-cli.sh --all --dry-run         # show plan, change nothing
#   ./install-cli.sh                         # interactive checklist menu
#   ./install-cli.sh --help
#
# AUTHORIZED USE ONLY. These are offensive-security / hardware-hacking tools.
# Install and use them only on systems you own or are explicitly permitted to
# test. You are responsible for compliance with all applicable laws.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
# shellcheck source=manifests/tools.sh
. "$HERE/manifests/tools.sh"
# shellcheck source=post/groups-udev.sh
. "$HERE/post/groups-udev.sh"
# shellcheck source=post/shell-extras.sh
. "$HERE/post/shell-extras.sh"

SELECTED=()          # category keys to install
WANT_GNURADIO=0
WANT_METASPLOIT=0
WANT_WORDLISTS=0
WANT_DOTFILES=0
: "${RUN_MODE:=cli}"  # "gui" when sourced by install-gui.sh; else default cli

usage() {
    cat <<EOF
loadout — provision a fresh Debian-family box with RE/pentest/SDR tooling.

Usage: ${0##*/} [CATEGORY FLAGS] [OPTIONS]

CLI categories:
$(for c in "${CLI_CATEGORIES[@]}"; do printf '  --%-12s %s\n' "$c" "${CAT_DESC[$c]}"; done)
  --all           Install every CLI category

Heavy opt-in payloads (bandwidth/disk):
  --metasploit    Metasploit Framework + DB init
  --wordlists     SecLists + rockyou (~1-2 GB)
  --gnuradio      Full GNU Radio stack

Options:
  --dry-run           Print the plan; make no changes
  --yes               Never prompt (unattended); implies repo confirmations
  --no-upgrade        Skip 'apt-get upgrade' of the base system
  --full-upgrade      dist-upgrade the base (may pull a new kernel -> reboot)
  --keep-kali-repo    Leave the pinned Kali repo in place after install
  --dotfiles          Install optional shell aliases/PATH snippet (~/.loadout.sh)
  --deep-clean        Also prune pip/cargo/go/apt caches at the end
  --latest            Fetch newest release binaries (unpinned, unverified)
  --require-checksum  Abort any release download that can't be checksum-verified
  -h, --help          This help

Examples:
  sudo ./install-cli.sh --all --yes
  sudo ./install-cli.sh --re --firmware --sdr
  ./install-cli.sh --all --dry-run
EOF
}

parse_args() {
    local a
    while [ "$#" -gt 0 ]; do
        a="$1"; shift
        case "$a" in
            --all)
                SELECTED=("${CLI_CATEGORIES[@]}")
                [ "$RUN_MODE" = "gui" ] && SELECTED+=("${GUI_CATEGORIES[@]}")
                ;;
            --gui)        SELECTED+=("${GUI_CATEGORIES[@]}") ;;   # all GUI categories
            --metasploit) WANT_METASPLOIT=1 ;;
            --wordlists)  WANT_WORDLISTS=1 ;;
            --gnuradio)   WANT_GNURADIO=1; export WANT_GNURADIO ;;
            --dotfiles)   WANT_DOTFILES=1 ;;
            --dry-run)    DRY_RUN=1 ;;
            --yes|-y)     ASSUME_YES=1 ;;
            --no-upgrade) DO_UPGRADE=0 ;;
            --full-upgrade) FULL_UPGRADE=1 ;;
            --keep-kali-repo) KEEP_KALI=1 ;;
            --deep-clean) DEEP_CLEAN=1 ;;
            --latest)     WANT_LATEST=1 ;;
            --require-checksum) REQUIRE_CHECKSUM=1 ;;
            -h|--help)    usage; exit 0 ;;
            --*)
                # Category flag?
                local key="${a#--}" found=0 c
                for c in "${CLI_CATEGORIES[@]}" "${GUI_CATEGORIES[@]}"; do
                    [ "$c" = "$key" ] && { SELECTED+=("$key"); found=1; break; }
                done
                [ "$found" = "1" ] || die "Unknown flag: $a (see --help)"
                ;;
            *) die "Unexpected argument: $a (see --help)" ;;
        esac
    done
}

# Interactive whiptail checklist when no category was chosen.
interactive_menu() {
    local cats=("${CLI_CATEGORIES[@]}")
    [ "$RUN_MODE" = "gui" ] && cats=("${CLI_CATEGORIES[@]}" "${GUI_CATEGORIES[@]}")
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
        local args=() c
        for c in "${cats[@]}"; do
            local on="OFF"; [ "$c" = "base" ] && on="ON"
            args+=("$c" "${CAT_DESC[$c]}" "$on")
        done
        local chosen
        chosen="$(whiptail --title "loadout" --checklist \
            "Select tool categories (space to toggle, enter to confirm):" \
            22 90 14 "${args[@]}" 3>&1 1>&2 2>&3)" || die "Cancelled."
        # whiptail returns quoted, space-separated keys
        eval "SELECTED=($chosen)"
    else
        # Fallback: numbered prompt
        echo "Select categories (space-separated numbers), then Enter:"
        local i=1 c
        for c in "${cats[@]}"; do printf '  %2d) %-13s %s\n' "$i" "$c" "${CAT_DESC[$c]}"; i=$((i+1)); done
        read -r -p "> " nums || true
        local n
        for n in $nums; do
            [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le "${#cats[@]}" ] 2>/dev/null \
                && SELECTED+=("${cats[$((n-1))]}")
        done
    fi
    [ "${#SELECTED[@]}" -gt 0 ] || die "Nothing selected."
}

# Dedup SELECTED and guarantee 'base' runs first.
normalize_selection() {
    local seen=" " out=() c
    # base always first
    out+=(base); seen=" base "
    for c in "${SELECTED[@]}"; do
        case "$seen" in *" $c "*) continue ;; esac
        out+=("$c"); seen="$seen$c "
    done
    SELECTED=("${out[@]}")
}

# Does the selection include any category that may pull Kali packages?
selection_touches_kali() {
    local c
    for c in "${SELECTED[@]}"; do
        case "$c" in re|pentest|gui_pentest|gui_forensics) return 0 ;; esac
    done
    [ "$WANT_METASPLOIT" = "1" ] || [ "$WANT_WORDLISTS" = "1" ]
}

main() {
    parse_args "$@"

    : >"$LOG_FILE" 2>/dev/null || true
    banner "loadout — $RUN_MODE installer  ($([ "$DRY_RUN" = 1 ] && echo DRY-RUN || echo LIVE))"

    setup_sudo
    resolve_target_user
    detect_os
    require_debian_family

    [ "${#SELECTED[@]}" -eq 0 ] && interactive_menu
    normalize_selection

    log "Selected: ${SELECTED[*]}"
    [ "$WANT_METASPLOIT" = 1 ] && log "  + metasploit"
    [ "$WANT_WORDLISTS"  = 1 ] && log "  + wordlists"
    [ "$WANT_GNURADIO"   = 1 ] && log "  + gnuradio"

    # --- Preflight ---
    check_clock
    local building=0
    case " ${SELECTED[*]} " in *" sdr "*|*" gui_sdr "*) [ "$WANT_GNURADIO" = 1 ] && building=1 ;; esac
    check_resources 15 "$building"

    # --- Ordered bring-up ---
    ensure_bootstrap_deps
    apt_upgrade
    preseed_debconf

    # base first (already index 0), then the rest
    local c
    for c in "${SELECTED[@]}"; do
        local fn="install_cat_$c"
        case "$c" in gui_*) fn="install_$c" ;; esac
        if declare -F "$fn" >/dev/null; then
            "$fn"
        else
            warn "No installer for category '$c' (skipping)."
        fi
    done

    # Heavy opt-ins
    [ "$WANT_WORDLISTS"  = 1 ] && install_wordlists
    [ "$WANT_METASPLOIT" = 1 ] && install_metasploit
    [ "$WANT_GNURADIO"   = 1 ] && case " ${SELECTED[*]} " in *" gui_sdr "*) : ;; *) install_gnuradio ;; esac

    # --- Post-install ---
    banner "post-install — groups + udev"
    add_user_groups plugdev dialout kvm libvirt wireshark
    install_udev_rules
    [ "$WANT_DOTFILES" = 1 ] && install_shell_extras

    # --- Kali repo teardown (default) ---
    disable_kali_repo

    # --- Cleanup + summary ---
    cleanup_apt
    print_summary
}

# Only auto-run when executed directly (install-gui.sh sources this file).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
