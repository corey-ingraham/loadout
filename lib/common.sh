# shellcheck shell=bash
# =============================================================================
# loadout — lib/common.sh
# Shared framework: logging, OS/arch detection, apt hygiene, install methods,
# Kali-repo pinning, groups/udev, preflight, cleanup, summary.
#
# Sourced by install-cli.sh / install-gui.sh. Not meant to run standalone.
# Requires: bash 4+, a Debian-family base (debian / ubuntu / raspbian / kali).
# =============================================================================

# --- Guard: must be sourced, and only once --------------------------------
if [ -n "${LOADOUT_COMMON_LOADED:-}" ]; then return 0 2>/dev/null || true; fi
LOADOUT_COMMON_LOADED=1

# --- Global state (defaults; overridden by the driver's arg parser) -------
: "${DRY_RUN:=0}"          # 1 = print actions, change nothing
: "${ASSUME_YES:=0}"       # 1 = never prompt (unattended)
: "${DO_UPGRADE:=1}"       # 1 = apt-get upgrade before installs (--no-upgrade -> 0)
: "${FULL_UPGRADE:=0}"     # 1 = dist-upgrade (may pull kernel -> reboot)
: "${KEEP_KALI:=0}"        # 1 = leave the Kali repo + pin in place after install
: "${DEEP_CLEAN:=0}"       # 1 = also prune pip/cargo/go caches at cleanup
: "${WANT_LATEST:=0}"      # 1 = rel tools fetch newest instead of pinned version
: "${REQUIRE_CHECKSUM:=0}" # 1 = abort a rel tool if no checksum can be verified
: "${LOG_FILE:=$HOME/loadout.log}"

# Accumulators for the end-of-run summary
INSTALLED_OK=()            # human labels of things we installed
SKIPPED_ITEMS=()           # "name (reason)"
FAILED_ITEMS=()            # "name (reason)"
NEED_KALI=0                # set to 1 when a selected tool required the Kali repo
NEED_REBOOT=0              # set to 1 when a change needs re-login/reboot
APT_UPDATED=0              # ensures apt-get update runs at most once
TEMP_SWAPFILE=""           # path if we added a build swapfile (removed at cleanup)

# --- Colors (disabled when not a TTY) -------------------------------------
if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
    C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_BOLD=$'\033[1m'
else
    C_RESET=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BOLD=""
fi

# --- Logging --------------------------------------------------------------
# Everything is tee'd to $LOG_FILE (plain, no color) via _logline.
_logline() { printf '%s %s\n' "$(_ts)" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
_ts()      { date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "----"; }

log()  { printf '%s[*]%s %s\n'  "$C_BLU" "$C_RESET" "$*"; _logline "[*] $*"; }
ok()   { printf '%s[OK]%s %s\n' "$C_GRN" "$C_RESET" "$*"; _logline "[OK] $*"; }
skip() { printf '%s[SKIP]%s %s\n' "$C_DIM" "$C_RESET" "$*"; _logline "[SKIP] $*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; _logline "[WARN] $*"; }
err()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; _logline "[FAIL] $*"; }
die()  { err "$*"; exit 1; }

hr()   { printf '%s============================================================%s\n' "$C_DIM" "$C_RESET"; }
banner() { hr; printf '%s  %s%s\n' "$C_BOLD" "$*" "$C_RESET"; hr; }

# --- run: dry-run-aware command execution ---------------------------------
# usage: run <cmd> [args...]   (respects DRY_RUN; logs the command)
run() {
    _logline "\$ $*"
    if [ "$DRY_RUN" = "1" ]; then
        printf '%s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
        return 0
    fi
    "$@"
}

# --- confirm: y/N prompt honoring ASSUME_YES ------------------------------
# usage: confirm "Question?"   -> returns 0 on yes
confirm() {
    local q="$1" ans
    if [ "$ASSUME_YES" = "1" ]; then return 0; fi
    if [ ! -t 0 ]; then
        # No TTY and not --yes: default to NO for safety.
        warn "No TTY to confirm \"$q\" and --yes not given; assuming NO."
        return 1
    fi
    printf '%s[?]%s %s [y/N] ' "$C_YEL" "$C_RESET" "$q"
    read -r ans || true
    case "${ans,,}" in y|yes) return 0 ;; *) return 1 ;; esac
}

# --- Privilege: $SUDO indirection -----------------------------------------
setup_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        # Prime the sudo timestamp early so long runs don't stall mid-install.
        [ "$DRY_RUN" = "1" ] || sudo -v || die "sudo authentication failed."
    else
        die "Not root and 'sudo' not found. Re-run as root or install sudo."
    fi
    export SUDO
}

# TARGET_USER / TARGET_HOME = the human whose account should get groups/PATH,
# even when we run under sudo.
resolve_target_user() {
    TARGET_USER="${SUDO_USER:-$(id -un)}"
    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
    [ -n "$TARGET_HOME" ] || TARGET_HOME="$HOME"
    export TARGET_USER TARGET_HOME
}

# =============================================================================
# OS / ARCH DETECTION
# =============================================================================
detect_os() {
    [ -r /etc/os-release ] || die "/etc/os-release missing; unsupported OS."
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    CODENAME="${VERSION_CODENAME:-}"
    ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    export DISTRO DISTRO_LIKE CODENAME ARCH
    log "Distro: ${PRETTY_NAME:-$DISTRO}  |  Arch: $ARCH  |  Codename: ${CODENAME:-?}"
}

is_debian_family() {
    case "$DISTRO" in debian|ubuntu|raspbian|kali|pop|linuxmint|devuan) return 0 ;; esac
    case " $DISTRO_LIKE " in *" debian "*|*" ubuntu "*) return 0 ;; esac
    return 1
}

require_debian_family() {
    is_debian_family || die "loadout targets Debian-family distros (apt). Detected: $DISTRO"
    command -v apt-get >/dev/null 2>&1 || die "apt-get not found; cannot continue."
}

# Kali-repo borrowing is only safe on Debian / Raspberry Pi OS, never Ubuntu.
kali_repo_allowed() {
    case "$DISTRO" in debian|raspbian|kali) return 0 ;; *) return 1 ;; esac
}

# is_amd64 / arch gate helper
arch_is() { [ "$ARCH" = "$1" ]; }

# =============================================================================
# PREFLIGHT
# =============================================================================
# Fresh Pi with no RTC boots at epoch -> TLS/GPG apt fetches fail. Fix or warn.
check_clock() {
    local yr
    yr="$(date +%Y 2>/dev/null || echo 1970)"
    if [ "$yr" -lt 2023 ] 2>/dev/null; then
        warn "System clock looks wrong (year=$yr). apt/TLS may fail on a bad clock."
        if command -v timedatectl >/dev/null 2>&1; then
            log "Enabling NTP time sync (timedatectl set-ntp true)..."
            run $SUDO timedatectl set-ntp true || true
            local i
            for i in 1 2 3 4 5 6 7 8 9 10; do
                yr="$(date +%Y)"; [ "$yr" -ge 2023 ] 2>/dev/null && break
                sleep 3
            done
        fi
        yr="$(date +%Y)"
        if [ "$yr" -lt 2023 ] 2>/dev/null; then
            warn "Clock still wrong; set it manually (e.g. 'sudo date -s ...') if apt fails."
        else
            ok "Clock synced (year=$yr)."
        fi
    fi
}

# Warn/abort on low disk; offer a temp swapfile on low RAM for source builds.
# usage: check_resources <need_gb_for_all> <building?0/1>
check_resources() {
    local need_gb="${1:-15}" building="${2:-0}"
    local avail_kb avail_gb
    avail_kb="$(df -Pk / 2>/dev/null | awk 'NR==2{print $4}')"
    avail_gb=$(( ${avail_kb:-0} / 1024 / 1024 ))
    log "Free disk on /: ${avail_gb} GB"
    if [ "$avail_gb" -lt "$need_gb" ]; then
        warn "Low disk (${avail_gb} GB < ${need_gb} GB recommended). Heavy categories may fail."
        confirm "Continue anyway?" || die "Aborting due to low disk."
    fi

    if [ "$building" = "1" ]; then
        local mem_kb mem_mb
        mem_kb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
        mem_mb=$(( mem_kb / 1024 ))
        local swap_kb; swap_kb="$(awk '/SwapTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
        if [ "$mem_mb" -lt 2048 ] && [ "$(( swap_kb / 1024 ))" -lt 1024 ]; then
            warn "Low RAM (${mem_mb} MB) and little swap; source builds may OOM-kill."
            if confirm "Add a temporary 2G swapfile for the build phase?"; then
                add_temp_swap
            fi
        fi
    fi
}

add_temp_swap() {
    local sf="/var/swap.loadout"
    [ -e "$sf" ] && { warn "$sf exists; not creating temp swap."; return 0; }
    log "Creating temporary 2G swapfile at $sf ..."
    if run $SUDO fallocate -l 2G "$sf" 2>/dev/null || run $SUDO dd if=/dev/zero of="$sf" bs=1M count=2048; then
        run $SUDO chmod 600 "$sf"
        run $SUDO mkswap "$sf" >/dev/null
        run $SUDO swapon "$sf" && { TEMP_SWAPFILE="$sf"; ok "Temp swap enabled."; }
    else
        warn "Could not create swapfile; continuing without it."
    fi
}

# =============================================================================
# APT HYGIENE
# =============================================================================
export DEBIAN_FRONTEND=noninteractive

apt_update_once() {
    [ "$APT_UPDATED" = "1" ] && return 0
    log "apt-get update ..."
    run $SUDO apt-get update -qq || warn "apt-get update reported errors (continuing)."
    APT_UPDATED=1
}

# Bootstrap deps must exist before ANY repo add or download.
ensure_bootstrap_deps() {
    log "Installing bootstrap dependencies ..."
    apt_update_once
    # apt-transport-https and software-properties-common are intentionally omitted:
    # apt has HTTPS support built in, and both were removed in Debian 13 (trixie) —
    # requesting them makes this single apt-get abort the entire bootstrap.
    run $SUDO apt-get install -y -qq \
        ca-certificates gnupg curl wget \
        lsb-release coreutils \
        || die "Failed to install bootstrap dependencies."
    ok "Bootstrap dependencies present."
}

apt_upgrade() {
    [ "$DO_UPGRADE" = "1" ] || { skip "base upgrade (--no-upgrade)"; return 0; }
    apt_update_once
    if [ "$FULL_UPGRADE" = "1" ]; then
        log "apt-get dist-upgrade (full) ..."
        run $SUDO apt-get dist-upgrade -y || warn "dist-upgrade had errors."
        NEED_REBOOT=1
    else
        log "apt-get upgrade (base) ..."
        run $SUDO apt-get upgrade -y || warn "upgrade had errors."
    fi
    ok "Base system upgraded."
}

# Preseed debconf answers for packages that would otherwise block on a prompt.
preseed_debconf() {
    command -v debconf-set-selections >/dev/null 2>&1 || return 0
    [ "$DRY_RUN" = "1" ] && { skip "debconf preseed (dry-run)"; return 0; }
    log "Preseeding debconf answers for non-interactive installs ..."
    $SUDO bash -c 'debconf-set-selections' <<'PRESEED' || warn "debconf preseed failed."
wireshark-common wireshark-common/install-setuid boolean true
kismet-capture-common kismet-capture-common/install-users string
kismet-capture-common kismet-capture-common/install-setuid boolean true
macchanger macchanger/automatically_run boolean false
sslh sslh/inetd_or_standalone select standalone
iperf3 iperf3/start_daemon boolean false
postfix postfix/main_mailer_type select No configuration
PRESEED
    ok "debconf preseeded."
}

# apt_install <label> <pkg...> : batch install; on failure retry per-package so one
# renamed/absent package (common across Debian releases) can't sink the whole group.
# Returns 0 if >=1 package installed, 1 if none — callers may chain a fallback with ||.
apt_install() {
    local label="$1"; shift
    [ "$#" -eq 0 ] && return 0
    apt_update_once
    if run $SUDO apt-get install -y -qq --no-install-recommends "$@"; then
        ok "apt: $label"
        INSTALLED_OK+=("$label")
        return 0
    fi
    warn "apt: $label batch failed; retrying per-package ..."
    local pkg _ok=0 _miss=""
    for pkg in "$@"; do
        if run $SUDO apt-get install -y -qq --no-install-recommends "$pkg"; then
            _ok=$((_ok + 1))
        else
            _miss="$_miss $pkg"
        fi
    done
    if [ "$_ok" -eq 0 ]; then
        err "apt: $label (none installable:$_miss)"
        FAILED_ITEMS+=("$label (apt)")
        return 1
    fi
    ok "apt: $label ($_ok installed${_miss:+; unavailable:$_miss})"
    INSTALLED_OK+=("$label")
    [ -n "$_miss" ] && FAILED_ITEMS+=("$label unavailable:$_miss")
    return 0
}

# =============================================================================
# LANGUAGE TOOLCHAINS + non-apt install methods
# =============================================================================
# pipx tools land in the TARGET_USER's ~/.local/bin. Ensure pipx + PATH.
ensure_pipx() {
    command -v pipx >/dev/null 2>&1 && return 0
    apt_install "pipx" pipx || return 1
    # Make this run's PATH see ~/.local/bin immediately.
    export PATH="$TARGET_HOME/.local/bin:$PATH"
}
pipx_install() {
    local label="$1"; shift
    ensure_pipx || { FAILED_ITEMS+=("$label (pipx unavailable)"); return 1; }
    local t
    for t in "$@"; do
        if pipx list 2>/dev/null | grep -qi "package $t "; then
            skip "pipx: $t (already installed)"; continue
        fi
        if run pipx install "$t"; then ok "pipx: $t"; INSTALLED_OK+=("$t")
        else err "pipx: $t"; FAILED_ITEMS+=("$t (pipx)"); fi
    done
}

ensure_go() {
    if command -v go >/dev/null 2>&1; then return 0; fi
    # Distro golang is often too old for modern go-install tools; prefer apt
    # here for simplicity but export a sane GOPATH/bin on PATH for the run.
    apt_install "golang" golang-go || return 1
    export PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin:/usr/local/go/bin"
}
go_install() {
    local label="$1"; shift   # remaining args are module@version specs
    ensure_go || { FAILED_ITEMS+=("$label (go unavailable)"); return 1; }
    export GOBIN="/usr/local/bin"
    local m
    for m in "$@"; do
        if run $SUDO env "PATH=$PATH" GOBIN=/usr/local/bin go install "$m"; then
            ok "go: ${m%@*}"; INSTALLED_OK+=("${m%@*}")
        else err "go: $m"; FAILED_ITEMS+=("$m (go)"); fi
    done
}

ensure_rust() {
    command -v cargo >/dev/null 2>&1 && return 0
    apt_install "rust/cargo" cargo || return 1
    export PATH="$TARGET_HOME/.cargo/bin:$PATH"
}
cargo_install() {
    local label="$1"; shift
    ensure_rust || { FAILED_ITEMS+=("$label (cargo unavailable)"); return 1; }
    local c
    for c in "$@"; do
        if command -v "$c" >/dev/null 2>&1; then skip "cargo: $c (present)"; continue; fi
        if run cargo install "$c"; then ok "cargo: $c"; INSTALLED_OK+=("$c")
        else err "cargo: $c"; FAILED_ITEMS+=("$c (cargo)"); fi
    done
}

# download_release: fetch a pinned artifact, verify, stage into /opt, symlink.
# usage: download_release <name> <url> <sha256|""> <archive_inner_bin|""> <symlink|"">
# - sha256 "" and no checksum -> WARN (or abort if REQUIRE_CHECKSUM=1)
download_release() {
    local name="$1" url="$2" sha="$3" inner="$4" link="$5"
    if command -v "$link" >/dev/null 2>&1 && [ -n "$link" ]; then
        skip "release: $name (present)"; return 0
    fi
    local dest="/opt/loadout/$name"
    local tmp; tmp="$(mktemp -d /tmp/loadout-build-XXXXXX)"
    local file="$tmp/${url##*/}"
    log "Downloading $name ..."
    if ! run curl --fail --location --retry 3 --retry-delay 2 --connect-timeout 15 \
            -o "$file" "$url"; then
        err "download: $name"; FAILED_ITEMS+=("$name (download)"); rm -rf "$tmp"; return 1
    fi
    # Checksum
    if [ -n "$sha" ]; then
        if echo "$sha  $file" | sha256sum -c - >/dev/null 2>&1; then
            ok "checksum: $name"
        else
            err "checksum MISMATCH: $name (expected $sha)"
            FAILED_ITEMS+=("$name (checksum)"); rm -rf "$tmp"; return 1
        fi
    elif [ "$REQUIRE_CHECKSUM" = "1" ]; then
        err "no checksum for $name and --require-checksum set"
        FAILED_ITEMS+=("$name (no checksum)"); rm -rf "$tmp"; return 1
    else
        warn "release $name is UNVERIFIED (no pinned sha256). Review before trusting."
    fi
    # Stage
    run $SUDO mkdir -p "$dest"
    case "$file" in
        *.zip)          run $SUDO unzip -q -o "$file" -d "$dest" ;;
        *.tar.gz|*.tgz) run $SUDO tar -xzf "$file" -C "$dest" ;;
        *.tar.xz)       run $SUDO tar -xJf "$file" -C "$dest" ;;
        *.tar.bz2)      run $SUDO tar -xjf "$file" -C "$dest" ;;
        *.AppImage)     run $SUDO cp "$file" "$dest/$name.AppImage" && run $SUDO chmod +x "$dest/$name.AppImage" ;;
        *)              run $SUDO cp "$file" "$dest/" ;;
    esac
    # Symlink the entry point
    if [ -n "$inner" ] && [ -n "$link" ]; then
        run $SUDO ln -sf "$dest/$inner" "/usr/local/bin/$link"
    elif [ -n "$link" ] && [ -f "$dest/$name.AppImage" ]; then
        run $SUDO ln -sf "$dest/$name.AppImage" "/usr/local/bin/$link"
    fi
    ok "release: $name -> $dest"
    INSTALLED_OK+=("$name")
    rm -rf "$tmp"
}

# =============================================================================
# KALI REPO (pinned, opt-in, removed by default afterwards)
# =============================================================================
KALI_LIST="/etc/apt/sources.list.d/kali-loadout.list"
KALI_PIN="/etc/apt/preferences.d/kali-loadout.pref"
KALI_KEY="/usr/share/keyrings/kali-loadout-archive-keyring.gpg"

enable_kali_repo() {
    [ -f "$KALI_LIST" ] && { NEED_KALI=1; return 0; }   # idempotent
    if ! kali_repo_allowed; then
        warn "Kali repo borrowing is only enabled on Debian/RaspiOS (not $DISTRO)."
        return 1
    fi
    log "A selected tool needs the Kali repo."
    warn "Kali rolling will be added but PINNED (priority 50) so it can NEVER"
    warn "silently upgrade your base system. Packages install only on request."
    confirm "Add the pinned Kali repo now?" || { warn "Skipping Kali-only tools."; return 1; }

    log "Fetching Kali archive keyring ..."
    if ! run bash -c "curl -fsSL https://archive.kali.org/archive-key.asc | $SUDO gpg --dearmor -o '$KALI_KEY'"; then
        err "Could not fetch/import Kali key."; return 1
    fi
    printf 'deb [signed-by=%s] https://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware\n' \
        "$KALI_KEY" | run $SUDO tee "$KALI_LIST" >/dev/null
    # Pin EVERYTHING from kali-rolling low so nothing installs unless we ask by name.
    # Also HARD-BLOCK kali-defaults (priority -1): it reconfigures the whole host
    # (prompt, sysctl, MOTD, users) and its preinst FAILS on non-Kali Debian, wedging
    # dpkg with "Unmet dependencies" for every later install. Blocking it makes packages
    # that hard-depend on it (e.g. seclists, wordlists) fail cleanly instead.
    cat <<PIN | run $SUDO tee "$KALI_PIN" >/dev/null
Package: *
Pin: release o=Kali
Pin-Priority: 50

Package: kali-defaults kali-tweaks
Pin: release *
Pin-Priority: -1
PIN
    APT_UPDATED=0; apt_update_once
    NEED_KALI=1
    ok "Kali repo added (pinned @50)."
}

# Install a Kali-only package by pinned target release.
kali_install() {
    local label="$1"; shift
    enable_kali_repo || { SKIPPED_ITEMS+=("$label (kali repo unavailable)"); return 1; }
    if run $SUDO apt-get install -y -qq -t kali-rolling "$@"; then
        ok "kali: $label"; INSTALLED_OK+=("$label"); return 0
    fi
    err "kali: $label"; FAILED_ITEMS+=("$label (kali)"); return 1
}

disable_kali_repo() {
    [ -f "$KALI_LIST" ] || return 0
    [ "$KEEP_KALI" = "1" ] && { log "Keeping Kali repo (--keep-kali-repo)."; return 0; }
    log "Removing Kali repo + pin (installed pkgs stay; future upgrades stay clean)."
    run $SUDO rm -f "$KALI_LIST" "$KALI_PIN"
    run $SUDO apt-get update -qq || true
    ok "Kali repo removed."
}

# =============================================================================
# POST-INSTALL: groups + udev
# =============================================================================
add_user_groups() {
    local g existing
    for g in "$@"; do
        getent group "$g" >/dev/null 2>&1 || continue          # group must exist
        if id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
            skip "group $g (already member)"; continue
        fi
        if run $SUDO usermod -aG "$g" "$TARGET_USER"; then
            ok "group: added $TARGET_USER to $g"; NEED_REBOOT=1
        else
            warn "could not add $TARGET_USER to $g"
        fi
    done
}

reload_udev() {
    command -v udevadm >/dev/null 2>&1 || return 0
    run $SUDO udevadm control --reload || true
    run $SUDO udevadm trigger || true
    NEED_REBOOT=1
}

# =============================================================================
# CLEANUP + SUMMARY
# =============================================================================
cleanup_apt() {
    log "Cleanup: autoremove + apt clean ..."
    run $SUDO apt-get autoremove --purge -y -qq || true
    run $SUDO apt-get clean || true
    rm -rf /tmp/loadout-build-* 2>/dev/null || true
    if [ "$DEEP_CLEAN" = "1" ]; then
        log "Deep clean: pruning pip/cargo/go/apt caches ..."
        rm -rf "$TARGET_HOME/.cache/pip" 2>/dev/null || true
        command -v go >/dev/null 2>&1 && go clean -cache 2>/dev/null || true
        run $SUDO rm -rf /var/lib/apt/lists/* 2>/dev/null || true
    fi
    if [ -n "$TEMP_SWAPFILE" ]; then
        log "Removing temporary swapfile $TEMP_SWAPFILE ..."
        run $SUDO swapoff "$TEMP_SWAPFILE" 2>/dev/null || true
        run $SUDO rm -f "$TEMP_SWAPFILE" 2>/dev/null || true
    fi
    unset DEBIAN_FRONTEND
    ok "Cleanup complete."
}

print_summary() {
    echo
    banner "loadout — summary"
    printf '%sInstalled/updated:%s %d item groups\n' "$C_GRN" "$C_RESET" "${#INSTALLED_OK[@]}"
    if [ "${#SKIPPED_ITEMS[@]}" -gt 0 ]; then
        printf '%sSkipped:%s\n' "$C_YEL" "$C_RESET"
        printf '  - %s\n' "${SKIPPED_ITEMS[@]}"
    fi
    if [ "${#FAILED_ITEMS[@]}" -gt 0 ]; then
        printf '%sFailed (review the log):%s\n' "$C_RED" "$C_RESET"
        printf '  - %s\n' "${FAILED_ITEMS[@]}"
    fi
    echo
    log "Full log: $LOG_FILE"
    if [ "$NEED_REBOOT" = "1" ]; then
        warn "Group / udev / kernel changes were made."
        warn "Log out & back in (or reboot) for group + device access to take effect."
    fi
    [ "${#FAILED_ITEMS[@]}" -eq 0 ]   # exit status reflects failures
}
