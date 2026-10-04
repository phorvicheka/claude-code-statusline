# Changelog

All notable changes to this statusline. The project has no tagged releases; entries are grouped by date.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] - 2026-10-04

### Security

- **Cache poisoning / code execution via `/tmp`.** The settings cache lived in a predictable world-writable
  path (`/tmp/claude-statusline`) and was loaded with `source`, so any local user who pre-created the directory
  could plant a file that ran as you on the next render. Cached numbers (git ahead/behind, width, transcript byte
  offset) also reached bash arithmetic, which evaluates `a[$(cmd)]`. Fixed at the root:
  - cache lives in `$XDG_RUNTIME_DIR/claude-statusline` (per-user, 0700) or `/tmp/claude-statusline-$UID`
    (created 0700); a symlink or a directory owned by someone else is refused and the statusline runs uncached;
  - cache files are never `source`d: the settings cache is read through a key whitelist with control characters
    stripped, and every cached value is validated (digits only / restricted charset) before use;
  - writes go to a private temp file and are renamed into place, so a symlink planted at a cache path is
    replaced instead of followed (no clobbering of files you own);
  - `TERM_WIDTH` from any source must be digits or it falls back to 200.
- `install.sh` / `uninstall.sh` use the same location and remove the old shared `/tmp/claude-statusline` only
  when it is yours and not a symlink.

### Fixed

- **Effort showed the wrong level (e.g. `high` while the session ran `xhigh`).** Claude Code sends `effort` and
  `thinking` as objects (`{"level":"xhigh"}`, `{"enabled":true}`). The script treated them as scalars, so `jq`
  aborted with `object can not be escaped for shell`, dropped every field emitted after it (including
  `transcript_path`), and fell back to the top-level `effortLevel` in settings, ignoring per-model
  `modelSettings.<model>.effortLevel`. Effort is now read from `effort.level`, which is the live session value
  (mid-session `/effort` changes and session-only `max` included).
- **Thinking always rendered off (`◇`)** because the object was stringified instead of read as `thinking.enabled`.
- **Shell injection through `eval`:** a hostile scalar in the payload (for example `thinking`) was executed as
  shell code. Every parsed field is now reduced to a shell-quoted scalar; objects, arrays and `null` become empty.
- **Haiku and other models without an effort parameter** no longer show a made-up `auto`/`high`: an absent
  `effort` key hides the effort element.
- **Vim `VISUAL LINE`** is now shown as `vim:VL` (it was indistinguishable from `VISUAL`).
- `install.sh` writes `settings.json` in place instead of `mv`, so file permissions and a symlinked profile
  settings file survive.

### Added

- **PR / merge-request badge from Claude Code's `pr.*` JSON** with review state (`✔` approved, `✗` changes
  requested, `draft`, `…` pending) and GitLab `MR #n` labelling.
- **Fast-mode badge** `⚡` (`fast_mode`), toggle `SHOW_FAST`.
- **Prompt-cache badge** `cache: 97% ↺~4m` / `cache: cold` (`prompt_cache`), full tier only, toggle `SHOW_CACHE`.
- **Gateway spend-limit meter** (`rate_limits.spend_limit`), toggle `SHOW_SPEND`.
- **`user@host:~/cwd`** on the host row (toggle `SHOW_CWD_PATH`, on by default). It is a flex segment: left-truncated
  to fit the row, dropped when there is no room, and dropped when the worktree row already prints the path.
- **Flex session name:** `s-name:` shrinks to the columns left on the row instead of wrapping it.
- **`statusLine.refreshInterval`** (60s) set by `install.sh` when absent (`STATUSLINE_REFRESH_INTERVAL=0` skips
  it). Keeps reset countdowns, cache TTL and git state moving while idle. It does not refresh rate-limit percentages.
- **`tests/run.sh`:** ~70 fixture cases (xhigh, max, Haiku, legacy payloads, null fields, hostile values,
  transcript cache, planted cache files and symlinks, PR states, badges, vim, worktree, widths) run in a sandboxed `HOME` and cache dir.
- `STATUSLINE_CACHE_DIR` env var to relocate the cache (used by the tests; the same symlink / ownership checks apply).
- Debug log now records which width source won (`env`, `COLUMNS` or `probe`).

### Changed

- **PR data no longer comes from `gh pr view`.** The `gh` CLI is not used and `install.sh` no longer checks for it.
  The PR badge's `✔`/`✗` now mean approved / changes requested (previously mergeable / conflicting).
- **Git cache TTL 300s -> 30s** (300s kept automatically for repos under `/mnt/*` via `GIT_CACHE_TTL_SLOW`), since
  the network call that forced the long TTL is gone. Cache files renamed `git2-*` / `settings2-*`; `install.sh`
  removes the old ones.
- **Advisor transcript scan is incremental and cached per session.** The old full `tac | grep` cost ~455ms per
  render on a 121MB transcript.
- **Worktree probing skipped** when `workspace.git_worktree` is absent on a current payload (saves git forks on
  every render); the worktree name comes from `workspace.git_worktree` when present.
- Remote URL for branch links comes from `workspace.repo` when present and handles any host (GitLab `/-/tree/`,
  Bitbucket `/src/`); SSH remotes are normalised for non-GitHub hosts too.
- `user@host` uses `$USER` / `$HOSTNAME` instead of forking `whoami` and `hostname`.
- Settings cache is keyed by cwd and model, and carries the per-model effort level (legacy payloads only).
- Measured (WSL2, native ext4, 2026-10-04): cold render 1129ms -> 335ms; warm render about +11ms versus the
  previous script (larger `jq` program), with the new features included.

### Docs

- README, `docs/anatomy.md` (effort/thinking sources, new elements), `configuration.md`, `performance.md`,
  `debugging.md`, `contributing.md`, `rate-limit-staleness.md`, `wsl2-cursor-troubleshooting.md` updated.

## 2026-05-26

- perf: raise cache TTLs for WSL2 `/mnt/*` hosts
- docs: WSL2 + Cursor troubleshooting guide

## 2026-04-27 / 2026-04-29

- perf: cache expensive lookups (git, settings, width)
- feat: worktree row (full-width path, branch hidden when it matches the git branch), layout restructure with the
  version next to the model, caveman-mode badge

## 2026-04-16 / 2026-04-21

- feat: `xhigh` effort level, `user@host`, advisor model display
- fix: auto-detect external git worktrees and detached-HEAD branches; split L1 so the cost/rate-limit row stays visible
- docs: Claude Code profile-management guide

## 2026-04-13 / 2026-04-15

- fix: terminal-width detection (Git Bash, no-TTY default), Windows backslash paths and `file://` URLs, ISO 8601
  rate-limit reset times, reset times at compact width, transcript parsing for session-only effort levels
- feat: `-y` flag for `install.sh`

## 2026-04-09 / 2026-04-14

- feat: initial Claude Code statusline v2 (thinking, effort, output style, colour-coded bars)
- docs: known limitations (clickable links, rate-limit freshness), cross-platform notes, debug hook
