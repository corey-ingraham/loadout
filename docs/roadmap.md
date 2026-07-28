# Roadmap

Forward-looking improvements. Newest first.
`RM-NNN` and `ISSUE-NNN` share **one counter** — next free number across this file and
[issues.md](issues.md). Next free: **RM-004**.

Status ∈ {planned, in-progress, done, deferred}.

### Format

```
### RM-NNN — title · status (YYYY-MM-DD)
**Goal:** what "done" looks like.
**Prerequisites:** what must exist first.
**Design questions:** open decisions.
```

---

### RM-003 — Pin SHA256 for every release binary · planned (2026-07-27)
**Goal:** no `download_release` entry lands unverified; `--require-checksum` becomes a viable default.
**Prerequisites:** enumerate unpinned entries in `manifests/tools.sh`; decide a pin-refresh cadence.
**Design questions:** who refreshes pins when upstream cuts a release — manual, or a checked-in helper script?

### RM-002 — Syntax + shellcheck CI · planned (2026-07-27)
**Goal:** every push runs `bash -n` over all scripts and `shellcheck` clean, so style/lint regressions can't merge.
**Prerequisites:** none — GitHub Actions on the existing remote.
**Design questions:** add a `debian:bookworm` container `--dry-run` smoke job too, accepting that
systemd/USB/hardware paths still can't be exercised in CI?

### RM-001 — armhf coverage audit · planned (2026-07-27)
**Goal:** a documented, tested list of what `[SKIP arch]`s on 32-bit Pi OS, so the README's guidance is exact.
**Prerequisites:** an armhf test target (real Pi or emulated).
**Design questions:** is armhf worth supporting at all, or should it warn-and-recommend 64-bit at preflight?
