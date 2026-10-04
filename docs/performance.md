# Performance

Statusline renders on every Claude Code TUI redraw. If a render takes longer than the redraw interval (~300ms), Claude Code stacks duplicate frames in scrollback during long thinking spans, leaving multiple statusline + input-box copies above the streaming output.

The script targets **< 200ms warm renders** to stay well under that ceiling.

## Benchmarks

Measured on WSL2 (Ubuntu, Linux 6.6, fork-heavy environment). Numbers will be lower on native Linux/macOS where bash `fork()` is ~10× cheaper.

| Phase | Before | After | Reduction |
|-------|--------|-------|-----------|
| Cold (no caches, `gh pr view` network) | ~2.15s | ~1.10s | **~49%** |
| Cold, after dropping `gh pr view` (2026-10-04, native ext4) | ~1.13s | ~0.34s | **~70%** |
| Warm (caches valid), best | ~410ms | ~140ms | **~65%** |
| Warm, median (WSL2 with system load) | ~430ms | ~250ms | **~40%** |
| Warm, p95 | ~600ms | ~340ms | **~43%** |

Variance on WSL2 is high (system load, fork tax). Native Linux/macOS will see warm renders consistently <100ms.

The remaining ~250ms warm cost on WSL2 is dominated by **subshell forks in `assemble_line`** (one fork per renderer × ~14 renderers × ~15ms WSL2 fork tax). Eliminating those would require refactoring renderers to mutate a global string instead of printing to stdout. Out of scope for now — listed under "Future work" below.

## Cache layout

All caches live in one private per-user directory and are short-lived. Delete it to force a refresh on next render. The directory is `$XDG_RUNTIME_DIR/claude-statusline/` (typically `/run/user/<uid>`), else `/tmp/claude-statusline-$UID/`, created mode 0700. If it is a symlink or owned by someone else, the statusline refuses it and runs uncached (slower, still correct). Cache files are plain data: they are parsed through a whitelist and never `source`d or evaluated, and writes are atomic and never follow a symlink.

```text
<cache dir>/
├── git2-<hash>              # branch, dirty, ahead/behind, remote (TTL 30s, 300s on /mnt/*)
├── settings2-<cwd+model>    # alwaysThinkingEnabled, effortLevel(+per-model), outputStyle, advisorModel (TTL 120s)
├── tx-advisor-<session>     # "<bytes scanned>\t<last /advisor value>": incremental transcript scan
├── tx-effort-<session>      # same, legacy (pre-`effort` JSON) payloads only
└── width-<parent-pid>       # fallback TERM_WIDTH probe only (TTL 300s); $COLUMNS is never cached
```

| Cache | TTL | Why | Tunable |
|-------|-----|-----|---------|
| Git | 30s (300s on `/mnt/*`) | Branch / dirty / ahead-behind. PR data is no longer here: it arrives in Claude Code's JSON (`pr.*`), so the old `gh pr view` network call (~1.5s cold) is gone. | `GIT_CACHE_TTL`, `GIT_CACHE_TTL_SLOW` |
| Settings | 120s | Avoids scattered `jq` calls across `settings.local.json` + `settings.json` (HOME and CWD). Keyed by cwd + model. | `SETTINGS_CACHE_TTL` |
| Transcript scan | per transcript growth | Transcripts reach 100MB+. A full `tac | grep` costs ~450ms; the cache remembers how many bytes were scanned and reads only the new tail. | n/a |
| Terminal width | 300s | Only the fallback probe. Claude Code exports `$COLUMNS`, which is used directly. | `WIDTH_CACHE_TTL` |

Reducing TTLs trades CPU for freshness. The defaults are tuned for "feels live but stays cheap" — bump them if your renders are still slow on a particular system.

## Optimizations applied

The current script already includes these wins. Listed here so you understand what each cache is for.

### 1. Settings preload (single-pass jq)

Three renderers (`render_thinking_effort`, `render_output_style`, `render_advisor`) used to call `jq` 6+ times across the same 4 settings files. Now one preload pass runs at startup with a single `jq` call per file extracting all 5 keys at once, populates `SETTINGS_*` globals, and renderers read those globals.

Files read in priority order (first non-empty wins):

1. `$CWD/.claude/settings.local.json`
2. `$HOME/.claude/settings.local.json`
3. `$CWD/.claude/settings.json`
4. `$HOME/.claude/settings.json`

### 2. Terminal width

`$COLUMNS` (exported by Claude Code) is used when present. Otherwise width detection walks `/proc/<pid>/stat` up to 5 ancestors looking for a parent pts device, because Claude Code does not pass a controlling terminal to statusline scripts. Cached per parent PID for 30s — survives across statusline invocations within a single Claude Code session.

Stale on terminal resize until TTL expires (30s max). Override by setting `TERM_WIDTH=<cols>` in the `statusLine.command` in `settings.json`.

### 3. Git cache, PR from JSON

`gh pr view` used to be the dominant cold-start cost (~1.5s, network) and forced a 300s git TTL. The PR badge now reads Claude Code's `pr.*` JSON fields, so the git cache holds only local data and a 30s TTL is cheap (`git status` ≈ 30ms on ext4). The cache key is the directory hash, so worktrees get independent caches.

### 3b. Worktree probing skipped

Claude Code's `workspace.git_worktree` says whether the cwd is a linked worktree. When it is absent on a current payload the script skips the `git rev-parse` probes that used to run on every render.

### 3c. Incremental transcript scan

`/advisor` is session-only, so the script looks for the last `Advisor set to …` line in the transcript. It remembers bytes scanned and the last hit per session, re-reading only appended bytes (plus 4KB overlap). Measured on a 121MB transcript: ~455ms per render for a full scan versus a stat call when unchanged.

### 4. Subshell-fork reductions

WSL2 fork is expensive (~10-30ms each). Hot paths replaced:

- `echo "$ab" | awk '{print $1}'` × 2 → single bash `read` (saved 2 forks per cache miss)
- 3× `printf | jq -r` for PR fields → 1× `jq` extracting TSV (saved 4 forks per cache miss)
- `cat "$file" | tr -d` → bash `read` + parameter expansion (saved 2 forks per render in `render_caveman`)
- `echo "$wt_git_info" | cut -f1` × 2 → single bash `read` with TSV split (saved 2 forks per render in `render_worktree`)

## Diagnosing slow renders

```bash
# Time a single render against your real working directory
cat > /tmp/sl-test.json <<EOF
{"session_id":"test","transcript_path":"","cwd":"$(pwd)","model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"workspace":{"current_dir":"$(pwd)","project_dir":"$(pwd)"},"version":"2.1.119","output_style":{"name":"default"},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_lines_added":0,"total_lines_removed":0}}
EOF

# Cold
rm -rf "$XDG_RUNTIME_DIR/claude-statusline" "/tmp/claude-statusline-$(id -u)"
time bash ~/.claude/statusline.sh < /tmp/sl-test.json > /dev/null

# Warm
time bash ~/.claude/statusline.sh < /tmp/sl-test.json > /dev/null
```

Targets:

- Warm < 200ms — healthy
- Warm 200-400ms — acceptable, watch for redraw stacking
- Warm > 400ms — investigate

If warm is slow, profile with:

```bash
PS4='+ $EPOCHREALTIME ' bash -x ~/.claude/statusline.sh < /tmp/sl-test.json > /dev/null 2> /tmp/trace.log

# Show steps that took > 5ms
awk '
/^\+ [0-9]/ {
  ts = $2 + 0
  line = $0; sub(/^\+ [0-9.]+ /, "", line)
  if (prev_ts > 0) {
    delta = ts - prev_ts
    if (delta > 0.005) printf "%.3fs | %.80s\n", delta, prev_line
  }
  prev_ts = ts; prev_line = line
}' /tmp/trace.log | sort -rn | head -15
```

## Tuning

Edit `~/.claude/statusline.sh` (or the package version + re-run install):

```bash
# ── Sizing ──
GIT_CACHE_TTL=30        # raise if git is slow on your repos; lower if branch changes lag
SETTINGS_CACHE_TTL=120  # raise/lower trade-off for output-style / advisor settings changes
WIDTH_CACHE_TTL=300     # fallback width probe only
```

Reset all caches: `rm -rf "$XDG_RUNTIME_DIR/claude-statusline" "/tmp/claude-statusline-$(id -u)"`

## Why this matters: TUI redraw stacking

Claude Code redraws the bottom region (status line + input box + statusline output) on tool events, token updates, and spinner ticks. If your statusline command takes longer than the redraw interval, frames pile up in scrollback rather than overwriting in place.

Symptoms:

- Multiple `❯` input prompts visible above streaming output
- Repeated statusline blocks separated by horizontal rules
- Worse during long `Ruminating…` spans (many redraws)
- Worse on WSL2 (fork-heavy)

The fix is making the statusline cheap. The caches above do that.

If you still see stacking after optimizing:

- Reduce `STATUSLINE_LINES` (e.g. `STATUSLINE_LINES=2 claude`) — fewer lines per stacked frame
- Use `Ctrl+L` to clear scrollback between long turns
- Try a faster terminal: WezTerm, Alacritty, Kitty all redraw better than Windows Terminal under WSL2
- File an issue at <https://github.com/anthropics/claude-code/issues> — the underlying cause is upstream, the script can only mitigate

## Future work

Remaining wins, not yet applied because they require larger refactors:

- **Eliminate subshell forks in `assemble_line`.** Each renderer is invoked as `seg=$($renderer)` which forks a subshell. With ~14 renderers per render this is ~210ms on WSL2. Refactor to write into a shared global (`SEG=""; $renderer; segments+=("$SEG")`) would save it. Touches every renderer.
- **Single-pass transcript scan.** Done in a different way: the scan is now incremental and cached (see 3c above).
