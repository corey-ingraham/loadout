# Changelog

Dated record of significant changes. Newest first. Dates are ISO 8601 (`YYYY-MM-DD`).

## 2026-07-27 — Repo docs scaffolded

- Added `CLAUDE.md` (reference-first, per global repo template) with critical rules and Applied Learning.
- Added `.gitignore` (secrets/env/keys blocklist + runtime `loadout.log`) — the repo previously had none.
- Added `docs/` registers: this changelog, [issues.md](issues.md), [roadmap.md](roadmap.md).

## 2026-07-27 — Debian 13 (trixie) compatibility

- Debian 13 support + more resilient apt handling (commit `8e4cfb0`).

## 2026-07-23 — Initial release

- Initial `loadout`: fresh Pi/Linux RE/pentest/SDR provisioner (commit `fafb3c6`).
- `bootstrap.sh` / `install-cli.sh` / `install-gui.sh`, `lib/common.sh` framework,
  `manifests/tools.sh` category data, `post/` groups+udev and shell extras.
