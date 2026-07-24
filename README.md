# loadout

**One-command provisioning for a fresh Raspberry Pi / Debian-family Linux box** — installs a full hardware & software reverse-engineering, pentest, SDR, cloning, and virtualization toolkit so you never hand-install this stuff again.

Two entry points:

- **`install-cli.sh`** — headless/CLI toolkit (works great over SSH on a Pi).
- **`install-gui.sh`** — everything in the CLI set **plus** desktop tools (Ghidra, Cutter, ImHex, SDR++, gqrx, URH, Burp Suite, Wireshark GUI, virt-manager…).

> ⚠️ **Authorized use only.** These are offensive-security and hardware-hacking tools. Install and use them **only** on systems you own or are explicitly authorized to test (labs, CTFs, your own hardware, sanctioned engagements). You are responsible for compliance with all applicable laws.

---

## Quickstart

```bash
git clone https://github.com/corey-ingraham/loadout.git
cd loadout

# See exactly what WOULD happen — changes nothing:
./install-cli.sh --all --dry-run

# Install everything (CLI), unattended:
sudo ./install-cli.sh --all --yes

# Pick categories:
sudo ./install-cli.sh --re --firmware --sdr --net

# Interactive checklist menu (no flags):
./install-cli.sh

# GUI superset on a desktop box:
sudo ./install-gui.sh --all
```

**Always `--dry-run` first on a new box.** It prints the resolved plan per category and touches nothing.

---

## What you get (categories)

| Flag | Category | Highlights |
|---|---|---|
| `--base` | Dev toolchain *(always installed)* | build-essential, git, python3/pipx, go, rust, node, ripgrep/fd/bat/fzf, usbutils |
| `--re` | Software RE | radare2, gdb + **gef**, binwalk, angr, pwntools, ropper, yara, capstone/unicorn |
| `--firmware` | Hardware/firmware RE | **mtd-utils (`nanddump`)**, flashrom, openocd (JTAG/SWD), avrdude, dfu-util, i2c/spi-tools, sigrok-cli, tio/minicom/picocom (serial), esptool |
| `--sdr` | Software-defined radio | rtl-sdr, hackrf, airspy, SoapySDR, multimon-ng, rtl_433, dump1090 |
| `--pentest` | Network/web/wireless | nmap, masscan, aircrack-ng, hydra/medusa, sqlmap, nikto, ffuf/nuclei/subfinder, netexec, impacket, + Kali staples (responder, wifite, kismet, bettercap) |
| `--cracking` | Hash/password | hashcat, john, hashid, crunch, cewl |
| `--cloning` | Imaging/forensics/recovery | ddrescue, dc3dd/dcfldd, testdisk/photorec, sleuthkit, foremost/scalpel, ewf-tools |
| `--net` | Telnet + connectivity | telnet, netcat, ncat, socat, httpie, mosh, arp-scan, netdiscover, mtr, dig/whois |
| `--virt` | Virtualization | qemu-system, **qemu-user-static** (cross-arch firmware emulation), libvirt |
| `--containers` | Containerization | Docker CE (official repo), podman, buildah, skopeo, lazydocker, dive |
| **GUI** | | |
| `--gui_re` | GUI RE | **Ghidra**, **Cutter**, **ImHex**, wxHexEditor, bless |
| `--gui_firmware` | GUI firmware | **PulseView** (logic analyzer) |
| `--gui_sdr` | GUI SDR | **SDR++**, gqrx, **URH**, inspectrum, CubicSDR |
| `--gui_pentest` | GUI pentest | **Burp Suite**, Wireshark GUI, BloodHound |
| `--gui_forensics` | GUI forensics | Autopsy, guymager |
| `--gui_virt` | GUI virtualization | virt-manager, VirtualBox *(amd64 only)* |

### Heavy opt-in payloads (off by default — kind to a small SD card)

| Flag | Pulls | Size |
|---|---|---|
| `--wordlists` | SecLists + rockyou | ~1–2 GB |
| `--metasploit` | Metasploit Framework + DB init | large |
| `--gnuradio` | Full GNU Radio stack | large |

---

## Options

```
--dry-run           Print the plan; make no changes
--yes, -y           Never prompt (unattended)
--no-upgrade        Skip 'apt-get upgrade' of the base system
--full-upgrade      dist-upgrade the base (may pull a new kernel -> reboot)
--keep-kali-repo    Leave the pinned Kali repo in place after install
--dotfiles          Install optional shell aliases + PATH snippet (~/.loadout.sh)
--deep-clean        Also prune pip/cargo/go/apt caches at the end
--latest            Fetch newest release binaries (unpinned, unverified)
--require-checksum  Abort any release download that can't be checksum-verified
-h, --help          Help
```

---

## How it works (and why it's safe on a fresh box)

The installers follow a strict order so a brand-new Pi doesn't trip over itself:

1. **Preflight** — verify Debian-family + detect arch; **fix a bad clock** (a Pi with no RTC boots at 1970 → every HTTPS/GPG `apt` fetch fails) via NTP; check free disk and offer a **temporary swapfile** on low-RAM boxes so source builds don't get OOM-killed.
2. **Bootstrap deps first** — `ca-certificates gnupg curl wget …` before any repo/download.
3. **`apt-get update` + base `upgrade`** — *before* any third-party repo, so the base system is coherent (skip with `--no-upgrade`).
4. **Preseed debconf** — answers the prompts (wireshark setuid, kismet, postfix, tzdata…) that would otherwise hang an unattended run.
5. **Install `base`**, then your selected categories.
6. **Post-install** — add you to `plugdev/dialout/kvm/libvirt/docker/wireshark`, install **udev rules** so serial/JTAG/logic-analyzer/SDR gear works without root.
7. **Cleanup** — `autoremove --purge`, `apt clean`, remove build scratch + temp swap.
8. **Summary** — what installed / skipped / failed, log path, and a reboot reminder.

Everything is **idempotent** — safe to re-run; already-present tools log `[SKIP]`. Per-tool failures are collected and reported at the end instead of aborting the whole run. A full log is written to `~/loadout.log`.

### Kali repo borrowing (the important safety detail)

Some tools (responder, wifite, kismet, bettercap, burpsuite, autopsy, detect-it-easy…) aren't in stock Debian/Ubuntu repos. When you select a category that needs them, loadout can add the **Kali rolling** repo — but it is **pinned to priority 50** (`Pin-Priority: 50`) so Kali packages install **only when explicitly requested by name** and can **never** silently upgrade your base system (which is how you brick a Pi). By default the repo + pin are **removed again after install** (`--keep-kali-repo` to retain). Kali borrowing is enabled only on **Debian / Raspberry Pi OS**, never Ubuntu.

### Architecture notes

- Works on **arm64 / amd64**; **armhf (32-bit Pi OS)** works but several release binaries (ImHex, VirtualBox, some GUI apps) are 64-bit only and will `[SKIP arch]`. **Use a 64-bit Raspberry Pi OS image** for best coverage.
- `hashcat` GPU acceleration is effectively CPU-only on a Pi.

### Release binary trust

Tools not in apt (Ghidra, Cutter, ImHex, lazydocker, dive…) are fetched as release artifacts. `download_release` verifies a **pinned SHA256** when one is set in `manifests/tools.sh`; entries without a pinned hash print an `[WARN] unverified` (use `--require-checksum` to hard-fail those, or `--latest` to accept newest-unpinned). **Review the pins in `manifests/tools.sh` before trusting them on a sensitive host** — you own that file.

---

## Repo layout

```
loadout/
├── bootstrap.sh          # curl|bash entrypoint: clones + dispatches
├── install-cli.sh        # headless installer (menu + flags)
├── install-gui.sh        # GUI superset (sources install-cli.sh)
├── lib/common.sh         # framework: logging, detect, apt, install methods, kali pin, cleanup
├── manifests/tools.sh    # DATA: per-category install functions + release pins
└── post/
    ├── groups-udev.sh    # udev rules for adapters/analyzers
    └── shell-extras.sh   # optional --dotfiles aliases/PATH
```

**Add a tool:** edit the relevant `install_cat_*` function in `manifests/tools.sh` — one line, no logic changes.

---

## Verify / test without touching a real host

```bash
# Syntax check everything
bash -n install-cli.sh install-gui.sh bootstrap.sh lib/common.sh manifests/tools.sh post/*.sh
shellcheck install-*.sh bootstrap.sh lib/*.sh manifests/*.sh post/*.sh   # if installed

# Dry-run the full plan
./install-cli.sh --all --dry-run
./install-gui.sh --all --dry-run

# Real end-to-end in a throwaway container (no risk to your machine)
docker run --rm -it debian:bookworm bash -c \
  'apt-get update && apt-get install -y git sudo && \
   git clone https://github.com/corey-ingraham/loadout /root/loadout && \
   cd /root/loadout && ./install-cli.sh --re --net --containers --yes'
```

> Plain containers have no systemd/USB, so service- and hardware-dependent bits (docker daemon, udev, SDR dongles) are validated on a real Pi/desktop, not in CI.

---

## Contributing / style

Bash, `set -euo pipefail`, 4-space indent, LF endings. Run `shellcheck` clean (config in `.shellcheckrc`) before committing.

## License

MIT — see [LICENSE](LICENSE).
