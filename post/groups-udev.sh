# shellcheck shell=bash
# =============================================================================
# loadout — post/groups-udev.sh
# udev rules so common hardware-hacking gear is usable without root.
# Sourced by the installers; provides install_udev_rules().
#
# SDR packages (rtl-sdr/hackrf/airspy) and openocd ship their own rules; this
# adds rules for serial/JTAG adapters and logic analyzers, all owned by the
# 'plugdev' group. Users must be in plugdev/dialout (handled by add_user_groups).
# =============================================================================

LOADOUT_UDEV_FILE="/etc/udev/rules.d/70-loadout.rules"

install_udev_rules() {
    banner "udev — non-root access for adapters/analyzers"
    local tmp; tmp="$(mktemp /tmp/loadout-udev-XXXXXX)"
    cat >"$tmp" <<'RULES'
# === loadout: hardware-hacking device access (group=plugdev) ===============
# Managed by loadout; overwrite-safe. Serial/JTAG/logic-analyzer/SDR adapters.

# --- USB-serial / UART adapters -------------------------------------------
# FTDI (FT232/FT2232/FT4232 etc.)
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", MODE="0660", GROUP="plugdev"
# Silicon Labs CP210x
SUBSYSTEM=="usb", ATTRS{idVendor}=="10c4", MODE="0660", GROUP="plugdev"
# WCH CH340/CH341
SUBSYSTEM=="usb", ATTRS{idVendor}=="1a86", MODE="0660", GROUP="plugdev"
# Prolific PL2303
SUBSYSTEM=="usb", ATTRS{idVendor}=="067b", MODE="0660", GROUP="plugdev"

# --- JTAG / SWD debug probes ----------------------------------------------
# ST-Link v2 / v2.1
SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="3748", MODE="0660", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="374b", MODE="0660", GROUP="plugdev"
# J-Link (SEGGER)
SUBSYSTEM=="usb", ATTRS{idVendor}=="1366", MODE="0660", GROUP="plugdev"
# CMSIS-DAP / DAPLink (ARM)
SUBSYSTEM=="usb", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0660", GROUP="plugdev"
# Bus Pirate / Buspirate-class (FTDI covered above; also Sparkfun)

# --- Logic analyzers -------------------------------------------------------
# Saleae Logic (original + Logic16 clones)
SUBSYSTEM=="usb", ATTRS{idVendor}=="0925", ATTRS{idProduct}=="3881", MODE="0660", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="21a9", MODE="0660", GROUP="plugdev"
# Generic FX2-based analyzers (fx2lafw / sigrok)
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", MODE="0660", GROUP="plugdev"

# --- SPI flash programmers -------------------------------------------------
# CH341A programmer (very common SPI flasher) — CH341 vendor covered above (1a86)
RULES

    if [ "$DRY_RUN" = "1" ]; then
        skip "udev rules (dry-run) -> would write $LOADOUT_UDEV_FILE"
        rm -f "$tmp"; return 0
    fi
    run $SUDO install -m 0644 "$tmp" "$LOADOUT_UDEV_FILE"
    rm -f "$tmp"
    ok "udev rules -> $LOADOUT_UDEV_FILE"
    reload_udev
}
