# loadout — Claude Code Reference

One-command provisioning for a fresh Raspberry Pi / Debian-family Linux box: installs a hardware & software
RE, pentest, SDR, cloning, and virtualization toolkit. Pure Bash, no runtime deps, idempotent.
**Authorized use only** — offensive-security tooling for owned/sanctioned systems (labs, CTFs, own hardware).

## Reference Docs

| Doc | Contents |
|---|---|
| [README](README.md) | **User-facing source of truth**: quickstart, every category flag + tool list, options, install order, Kali-pin safety model, arch notes, release-binary trust, test recipes |
| [Changelog](docs/changelog.md) | Dated record of significant changes |
| [Issues](docs/issues.md) | Problems, incidents, resolved defects (ISSUE-NNN) |
| [Roadmap](docs/roadmap.md) | Forward-looking improvements (RM-NNN) |

Do not restate README content here — link to it.

---

## Quick Facts

| Item | Detail |
|---|---|
| Language | Bash, `set -euo pipefail`, 4-space indent, LF endings |
| Targets | Debian family (Debian 12/13, Raspberry Pi OS, Ubuntu); arm64 / amd64 (armhf partial) |
| Entry points | `bootstrap.sh` (curl\|bash) → `install-cli.sh` (headless) / `install-gui.sh` (superset, sources CLI) |
| Framework | `lib/common.sh` — logging, OS/arch detect, apt, pipx/go/cargo, `download_release`, Kali pin, cleanup |
| Tool data | `manifests/tools.sh` — `install_cat_*()` per category + pinned release SHA256s |
| Post-install | `post/groups-udev.sh` (groups + udev rules), `post/shell-extras.sh` (`--dotfiles`) |
| Runtime log | `~/loadout.log` |
| Remote | `github.com/corey-ingraham/loadout` |
| Secrets | None — this repo holds no credentials; never add any |

---

## Critical Rules

1. **`--dry-run` is sacred** — it must print the plan and change nothing. Never let a code path write, install, or fetch under dry-run.
2. **Idempotent always** — re-running is safe; already-present tools log `[SKIP]`, not a reinstall or an error.
3. **Fail soft, report loud** — a per-tool failure is collected and shown in the summary; it must not abort the whole run.
4. **Data vs. logic split** — adding a tool means one line in `manifests/tools.sh`; `lib/common.sh` holds behavior. Don't put tool lists in the library or logic in the manifest.
5. **Kali repo stays pinned to 50 and is removed after install** (unless `--keep-kali-repo`); Debian/Pi OS only, never Ubuntu. Weakening this can brick a Pi — treat the pin as a safety invariant.
6. **Install order is load-bearing** — preflight (clock/disk/swap) → bootstrap deps → `apt update` + base upgrade → preseed debconf → base → categories → post → cleanup. A fresh Pi breaks if reordered.
7. **Clock fix before any HTTPS/GPG fetch** — a Pi with no RTC boots at 1970 and every apt fetch fails.
8. **Preseed anything interactive** — an unattended run must never hang on debconf (wireshark setuid, kismet, postfix, tzdata).
9. **Pin release binaries** — new `download_release` entries need a SHA256 in `manifests/tools.sh`; unpinned prints `[WARN] unverified`.
10. **Arch-guard 64-bit-only payloads** — emit `[SKIP arch]`, never a hard failure, on armhf.
11. **shellcheck clean** before committing (config in `.shellcheckrc`).

---

## Quick Reference

| Task | Command |
|---|---|
| Syntax check all | `bash -n install-cli.sh install-gui.sh bootstrap.sh lib/common.sh manifests/tools.sh post/*.sh` |
| Lint | `shellcheck install-*.sh bootstrap.sh lib/*.sh manifests/*.sh post/*.sh` |
| Plan only (safe) | `./install-cli.sh --all --dry-run` |
| Full unattended | `sudo ./install-cli.sh --all --yes` |
| Category subset | `sudo ./install-cli.sh --re --firmware --sdr --net` |
| Throwaway e2e | `docker run --rm -it debian:bookworm bash -c '…clone… && ./install-cli.sh --re --net --yes'` |

Category flags and their tool inventories → [README](README.md#what-you-get-categories).

---

## Applied Learning

> Add a bullet when something fails repeatedly, Corey re-explains, a workaround is found, or a
> token-saving pattern emerges. Max 15 words per bullet. No explanations. Future-session value only.

- Pi with no RTC boots at 1970 — fix clock before any apt/HTTPS fetch.
- Kali repo must stay `Pin-Priority: 50`; unpinned Kali upgrades brick a Pi.
- Containers lack systemd/USB — validate docker/udev/SDR on real hardware, not CI.
- armhf lacks many release binaries; prefer 64-bit Pi OS images.

---

## Response Style

- **BLUF first** — direct answer in 1–3 sentences, then detail
- **Full code** — complete replacement of a function, not a snippet fragment
- **Exact** — real flag names, real function names, real file paths
- Verify with `bash -n` + `--dry-run` before calling a change done
- No trailing summaries
