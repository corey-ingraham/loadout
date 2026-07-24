# shellcheck shell=bash
# =============================================================================
# loadout — manifests/tools.sh
# DATA + per-category install functions. Sourced after lib/common.sh.
#
# Each CLI category is install_cat_<name>; each GUI category is install_gui_<name>.
# Adding a tool = add it to the relevant helper call below. Install methods come
# from lib/common.sh: apt_install / pipx_install / go_install / cargo_install /
# kali_install / download_release.
#
# Release pins: version + URL are pinned. SHA256 is filled where a stable value
# is known; entries with an empty sha print an [WARN] "unverified" unless you set
# --require-checksum. Review/OWN these before trusting on a sensitive host.
# =============================================================================

# --- Category registry (order = menu order) -------------------------------
CLI_CATEGORIES=(base re firmware sdr pentest cracking cloning net virt containers)
GUI_CATEGORIES=(gui_re gui_firmware gui_sdr gui_pentest gui_forensics gui_virt)

declare -A CAT_DESC=(
    [base]="Core dev toolchain + plumbing (always installed)"
    [re]="Software reverse engineering (radare2, gdb+gef, angr, pwntools, binwalk)"
    [firmware]="Hardware/firmware RE + buses (mtd-utils/nanddump, flashrom, openocd, serial)"
    [sdr]="Software-defined radio CLI (rtl-sdr, hackrf, soapy, multimon-ng)"
    [pentest]="Network/web/wireless pentest (nmap, aircrack, hydra, ffuf, netexec)"
    [cracking]="Hash/password cracking (hashcat, john, hashid, crunch)"
    [cloning]="Imaging/forensics/recovery (ddrescue, dc3dd, testdisk, sleuthkit)"
    [net]="Telnet + connectivity (telnet, netcat, socat, httpie, arp-scan)"
    [virt]="Virtualization (qemu, qemu-user-static, libvirt) + cross-arch emu"
    [containers]="Containerization (docker, podman, buildah, lazydocker, dive)"
    [gui_re]="GUI RE (Ghidra, Cutter, ImHex, hex editors)"
    [gui_firmware]="GUI firmware (PulseView logic analyzer)"
    [gui_sdr]="GUI SDR (SDR++, gqrx, URH, inspectrum, CubicSDR)"
    [gui_pentest]="GUI pentest (Burp Suite, Wireshark GUI, BloodHound)"
    [gui_forensics]="GUI forensics (Autopsy, guymager)"
    [gui_virt]="GUI virtualization (virt-manager, VirtualBox[amd64])"
)

# =============================================================================
# CLI CATEGORIES
# =============================================================================

install_cat_base() {
    banner "base — dev toolchain + plumbing"
    apt_install "build/dev core" \
        build-essential git curl wget vim neovim tmux htop tree jq \
        ripgrep fd-find bat fzf ncdu unzip zip p7zip-full xz-utils \
        ca-certificates gnupg pass \
        python3 python3-pip pipx python3-venv \
        nodejs npm \
        usbutils pciutils dmidecode lshw net-tools iproute2 \
        whiptail file less
    # gh (GitHub CLI) — apt on newer, else skip w/ note
    if ! command -v gh >/dev/null 2>&1; then
        apt_install "gh (github-cli)" gh || SKIPPED_ITEMS+=("gh (not in this repo; see cli.github.com)")
    fi
    ensure_pipx; ensure_go; ensure_rust
}

install_cat_re() {
    banner "re — software reverse engineering"
    apt_install "re core" \
        radare2 gdb binutils ltrace strace upx-ucl yara \
        bsdextrautils hexedit xxd foremost \
        python3-capstone python3-unicorn python3-keystone
    pipx_install "angr" angr
    pipx_install "pwntools" pwntools
    pipx_install "ropper" ropper
    pipx_install "ROPgadget" ROPgadget
    # gef (GDB Enhanced Features) — user-level, no apt pkg
    _install_gef
    # Detect It Easy (CLI) via Kali if available
    kali_install "detect-it-easy (die)" detect-it-easy || true
}

_install_gef() {
    local rc="$TARGET_HOME/.gdbinit"
    if grep -q "gef.py" "$rc" 2>/dev/null; then skip "gef (already in .gdbinit)"; return 0; fi
    if [ "$DRY_RUN" = "1" ]; then skip "gef (dry-run) -> would install to $rc"; return 0; fi
    log "Installing gef (GDB enhanced) for $TARGET_USER ..."
    if run bash -c "curl -fsSL https://raw.githubusercontent.com/hugsy/gef/main/gef.py -o '$TARGET_HOME/.gef.py'"; then
        printf 'source %s/.gef.py\n' "$TARGET_HOME" >>"$rc"
        run chown "$TARGET_USER":"$TARGET_USER" "$rc" "$TARGET_HOME/.gef.py" 2>/dev/null || true
        ok "gef installed"
        INSTALLED_OK+=("gef")
    else
        warn "gef fetch failed"; FAILED_ITEMS+=("gef (download)")
    fi
}

install_cat_firmware() {
    banner "firmware — hardware/firmware RE + buses"
    apt_install "firmware/bus tools" \
        mtd-utils flashrom openocd avrdude dfu-util \
        i2c-tools spi-tools sigrok-cli \
        minicom picocom screen tio srecord \
        binwalk sasquatch 2>/dev/null || \
    apt_install "firmware/bus tools (core)" \
        mtd-utils flashrom openocd avrdude dfu-util \
        i2c-tools sigrok-cli minicom picocom screen tio srecord binwalk
    pipx_install "esptool" esptool
}

install_cat_sdr() {
    banner "sdr — software-defined radio (CLI)"
    apt_install "sdr core" \
        rtl-sdr hackrf airspy soapysdr-tools \
        libsoapysdr-dev multimon-ng rtl-433 dump1090-mutable
    # SoapySDR device modules (best-effort; names vary by release)
    apt_install "soapy modules" soapysdr-module-rtlsdr soapysdr-module-hackrf soapysdr-module-airspy 2>/dev/null || \
        SKIPPED_ITEMS+=("some soapy modules (not packaged on this release)")
    log "Heavy GNU Radio is opt-in via --gnuradio (installed in GUI run)."
}

install_gnuradio() {
    banner "gnuradio (heavy, opt-in)"
    apt_install "gnuradio" gnuradio gnuradio-dev gr-osmosdr
}

install_cat_pentest() {
    banner "pentest — network/web/wireless"
    apt_install "pentest core" \
        nmap masscan tshark tcpdump aircrack-ng \
        hydra medusa ncrack sqlmap nikto \
        gobuster dirb whatweb wfuzz \
        smbclient proxychains4 tor dnsrecon \
        ettercap-text-only
    pipx_install "netexec" netexec
    pipx_install "impacket" impacket
    pipx_install "theHarvester" theHarvester
    # Go-based web/recon tools (newest from source)
    go_install "ffuf"      github.com/ffuf/ffuf/v2@latest
    go_install "nuclei"    github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
    go_install "subfinder" github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
    go_install "httpx"     github.com/projectdiscovery/httpx/cmd/httpx@latest
    # Kali-only staples
    kali_install "responder" responder || true
    kali_install "wifite / reaver / bully / kismet" wifite reaver bully kismet || true
    kali_install "enum4linux + exploitdb(searchsploit)" enum4linux exploitdb || true
    kali_install "bettercap" bettercap || true
    kali_install "feroxbuster" feroxbuster || true
}

install_metasploit() {
    banner "metasploit (heavy, opt-in)"
    # Prefer Kali package; fall back to official nightly installer.
    if kali_install "metasploit-framework" metasploit-framework; then :; else
        log "Falling back to Rapid7 nightly installer ..."
        run bash -c 'curl -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb -o /tmp/msfinstall && chmod +x /tmp/msfinstall && '"$SUDO"' /tmp/msfinstall' \
            && { ok "metasploit (nightly)"; INSTALLED_OK+=("metasploit-framework"); } \
            || { err "metasploit"; FAILED_ITEMS+=("metasploit"); }
    fi
    if command -v msfdb >/dev/null 2>&1; then
        log "Initializing Metasploit database (msfdb init) ..."
        run msfdb init || warn "msfdb init failed (run it manually later)."
    fi
}

install_cat_cracking() {
    banner "cracking — hash/password"
    apt_install "cracking core" \
        hashcat john hashid crunch cewl wordlists ophcrack-cli 2>/dev/null || \
    apt_install "cracking core" hashcat john hashid crunch cewl
    arch_is amd64 || warn "hashcat GPU acceleration is limited/absent on $ARCH (CPU only)."
}

install_wordlists() {
    banner "wordlists (heavy, opt-in)"
    apt_install "seclists + wordlists" seclists wordlists 2>/dev/null || \
        kali_install "seclists" seclists || {
            log "apt/kali seclists unavailable; cloning SecLists (shallow) ..."
            run $SUDO git clone --depth 1 https://github.com/danielmiessler/SecLists.git /usr/share/seclists \
                && { ok "SecLists cloned"; INSTALLED_OK+=("SecLists"); } \
                || FAILED_ITEMS+=("SecLists (clone)")
        }
    # Gunzip rockyou if present but compressed
    if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
        run $SUDO gunzip -k /usr/share/wordlists/rockyou.txt.gz && ok "rockyou unpacked"
    fi
}

install_cat_cloning() {
    banner "cloning — imaging/forensics/recovery"
    apt_install "cloning core" \
        gddrescue dc3dd dcfldd rsync partclone \
        testdisk foremost scalpel sleuthkit ewf-tools \
        exfatprogs dosfstools ntfs-3g gpart
}

install_cat_net() {
    banner "net — telnet + connectivity"
    apt_install "net core" \
        telnet netcat-openbsd ncat socat \
        openssh-client mosh httpie iperf3 \
        arp-scan netdiscover mtr-tiny dnsutils whois \
        rlwrap
}

install_cat_virt() {
    banner "virt — virtualization + cross-arch emulation"
    apt_install "virt core" \
        qemu-system qemu-utils qemu-user-static binfmt-support \
        libvirt-daemon-system libvirt-clients bridge-utils virtinst
    # Ensure binfmt handlers are registered for foreign-arch firmware binaries
    if command -v update-binfmts >/dev/null 2>&1; then
        run $SUDO update-binfmts --enable 2>/dev/null || true
    fi
}

install_cat_containers() {
    banner "containers — docker + podman ecosystem"
    # Docker: prefer the official repo on Debian/RaspiOS; else distro docker.io
    if _install_docker_official; then :; else
        apt_install "docker.io + compose" docker.io docker-compose-plugin
    fi
    apt_install "podman ecosystem" podman buildah skopeo uidmap
    # TUI helpers via release binaries (small, single-file Go)
    download_release "lazydocker" \
        "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_Linux_$(_go_arch).tar.gz" \
        "" "lazydocker" "lazydocker"
    download_release "dive" \
        "https://github.com/wagoodman/dive/releases/latest/download/dive_linux_$(_go_arch_dash).tar.gz" \
        "" "dive" "dive"
    add_user_groups docker
}

_install_docker_official() {
    kali_repo_allowed || return 1   # only on debian/raspbian here
    command -v docker >/dev/null 2>&1 && { skip "docker (present)"; return 0; }
    log "Installing Docker CE from the official repo ..."
    local key=/usr/share/keyrings/docker-loadout.gpg
    run bash -c "curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | $SUDO gpg --dearmor -o '$key'" || return 1
    printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/%s %s stable\n' \
        "$ARCH" "$key" "$DISTRO" "$CODENAME" | run $SUDO tee /etc/apt/sources.list.d/docker-loadout.list >/dev/null
    APT_UPDATED=0; apt_update_once
    apt_install "docker-ce" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    return 0
}

# arch helpers for release URLs
_go_arch()      { case "$ARCH" in amd64) echo x86_64 ;; arm64) echo arm64 ;; armhf) echo armv6 ;; *) echo "$ARCH" ;; esac; }
_go_arch_dash() { case "$ARCH" in amd64) echo amd64 ;; arm64) echo arm64 ;; *) echo "$ARCH" ;; esac; }

# =============================================================================
# GUI CATEGORIES (install-gui.sh)
# =============================================================================

install_gui_re() {
    banner "gui_re — Ghidra, Cutter, ImHex, hex editors"
    apt_install "JDK + GUI hex editors" default-jdk wxhexeditor bless
    # Ghidra (needs JDK 17+); pinned release.
    download_release "ghidra" \
        "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.1.2_build/ghidra_11.1.2_PUBLIC_20240709.zip" \
        "" "ghidra_11.1.2_PUBLIC/ghidraRun" "ghidra"
    # Cutter (rizin GUI) AppImage
    download_release "cutter" \
        "https://github.com/rizinorg/cutter/releases/latest/download/Cutter-Linux-$(_go_arch).AppImage" \
        "" "" "cutter"
    # ImHex AppImage (amd64/arm64 only)
    if arch_is amd64 || arch_is arm64; then
        download_release "imhex" \
            "https://github.com/WerWolv/ImHex/releases/latest/download/imhex-Linux-$(_go_arch).AppImage" \
            "" "" "imhex"
    else
        SKIPPED_ITEMS+=("imhex ($ARCH unsupported)")
    fi
}

install_gui_firmware() {
    banner "gui_firmware — PulseView logic analyzer"
    apt_install "pulseview + sigrok" pulseview sigrok-firmware-fx2lafw
}

install_gui_sdr() {
    banner "gui_sdr — SDR++, gqrx, URH, inspectrum"
    apt_install "gqrx + inspectrum + cubicsdr" gqrx-sdr inspectrum cubicsdr
    pipx_install "urh (Universal Radio Hacker)" urh
    # SDR++ nightly (unversioned upstream URL -> unverified; warns)
    download_release "sdrpp" \
        "https://github.com/AlexandreRouma/SDRPlusPlus/releases/download/nightly/sdrpp_debian_bookworm_amd64.deb" \
        "" "" "" 2>/dev/null || SKIPPED_ITEMS+=("SDR++ (install manually; nightly URL is release-specific)")
    [ "${WANT_GNURADIO:-0}" = "1" ] && install_gnuradio
}

install_gui_pentest() {
    banner "gui_pentest — Burp, Wireshark GUI, BloodHound"
    preseed_debconf
    apt_install "wireshark GUI" wireshark
    add_user_groups wireshark
    kali_install "burpsuite" burpsuite || SKIPPED_ITEMS+=("Burp Suite (download from portswigger.net)")
    kali_install "bloodhound + neo4j" bloodhound neo4j || SKIPPED_ITEMS+=("BloodHound (see bloodhound.readthedocs.io)")
}

install_gui_forensics() {
    banner "gui_forensics — Autopsy, guymager"
    apt_install "guymager" guymager
    kali_install "autopsy" autopsy || SKIPPED_ITEMS+=("Autopsy (see sleuthkit.org/autopsy)")
}

install_gui_virt() {
    banner "gui_virt — virt-manager, VirtualBox"
    apt_install "virt-manager" virt-manager
    if arch_is amd64; then
        apt_install "virtualbox" virtualbox || SKIPPED_ITEMS+=("VirtualBox (add Oracle repo if not in distro)")
    else
        skip "VirtualBox ($ARCH — amd64 only)"
        SKIPPED_ITEMS+=("VirtualBox (amd64 only)")
    fi
}
