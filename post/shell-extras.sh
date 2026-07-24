# shellcheck shell=bash
# =============================================================================
# loadout — post/shell-extras.sh
# Optional (--dotfiles) quality-of-life shell tweaks. Idempotent, additive:
# writes a single sourced snippet and links it from the target user's rc file.
# Never overwrites the user's existing rc.
# =============================================================================

LOADOUT_SNIPPET="$HOME/.loadout.sh"

install_shell_extras() {
    banner "shell-extras — aliases + PATH (opt-in --dotfiles)"
    LOADOUT_SNIPPET="$TARGET_HOME/.loadout.sh"
    local tmp; tmp="$(mktemp /tmp/loadout-rc-XXXXXX)"
    cat >"$tmp" <<'SNIP'
# === loadout shell extras (sourced from ~/.bashrc) =========================
# Tool bin dirs
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"

# Handy aliases for the installed kit
alias ll='ls -alh'
alias serial='ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null'
alias ports='ss -tulpn'
alias myip='ip -brief addr'
command -v batcat >/dev/null 2>&1 && alias bat='batcat'
command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'
alias httpx-serve='python3 -m http.server'
# Quick serial console: sercon /dev/ttyUSB0 [baud]
sercon() { tio "${1:-/dev/ttyUSB0}" -b "${2:-115200}" 2>/dev/null || screen "${1:-/dev/ttyUSB0}" "${2:-115200}"; }
SNIP

    if [ "$DRY_RUN" = "1" ]; then
        skip "shell-extras (dry-run) -> would write $LOADOUT_SNIPPET"
        rm -f "$tmp"; return 0
    fi

    run install -m 0644 "$tmp" "$LOADOUT_SNIPPET"
    run chown "$TARGET_USER":"$TARGET_USER" "$LOADOUT_SNIPPET" 2>/dev/null || true
    rm -f "$tmp"

    local rc="$TARGET_HOME/.bashrc"
    if [ -f "$rc" ] && ! grep -q '.loadout.sh' "$rc" 2>/dev/null; then
        printf '\n# loadout\n[ -f "$HOME/.loadout.sh" ] && . "$HOME/.loadout.sh"\n' >>"$rc"
        ok "linked shell-extras from ~/.bashrc"
    else
        skip "shell-extras (already linked or no ~/.bashrc)"
    fi
    INSTALLED_OK+=("shell-extras")
}
