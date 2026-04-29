# Performance

Statusline renders on every Claude Code TUI redraw. If a render takes longer than the redraw interval (~300ms), Claude Code stacks duplicate frames in scrollback during long thinking spans, leaving multiple statusline + input-box copies above the streaming output.

The script targets **< 200ms warm renders** to stay well under that ceiling.

## Benchmarks

Measured on WSL2 (Ubuntu, Linux 6.6, fork-heavy environment). Numbers will be lower on native Linux/macOS where bash `fork()` is ~10× cheaper.

| Phase | Before | After | Reduction |
|-------|--------|-------|-----------|
| Cold (no caches, `gh pr view` network) | ~2.15s | ~1.10s | **~49%** |
| Warm (caches valid), best | ~410ms | ~140ms | **~65%** |
| Warm, median (WSL2 with system load) | ~430ms | ~250ms | **~40%** |
| Warm, p95 | ~600ms | ~340ms | **~43%** |

Variance on WSL2 is high (system load, fork tax). Native Linux/macOS will see warm renders consistently <100ms.

The remaining ~250ms warm cost on WSL2 is dominated by **subshell forks in `assemble_line`** (one fork per renderer × ~14 renderers × ~15ms WSL2 fork tax). Eliminating those would require refactoring renderers to mutate a global string instead of printing to stdout. Out of scope for now — listed under "Future work" below.

## Cache layout

All caches live under `/tmp/claude-statusline/` and are short-lived. Delete the directory to force a refresh on next render.

```text
/tmp/claude-statusline/
├── git-<hash>          # branch, dirty, ahead/behind, remote, PR data (TTL 60s)
├── settings-<cwd-hash> # alwaysThinkingEnabled, effortLevel, outputStyle, advisorModel (TTL 30s)
└── width-<parent-pid>  # cached TERM_WIDTH (TTL 30s)
```

| Cache | TTL | Why | Tunable |
|-------|-----|-----|---------|
| Git + PR | 60s | `gh pr view` is a network call (~1.5s cold). Branch / dirty rarely change in <1 min. | `GIT_CACHE_TTL` in statusline.sh |
| Settings | 30s | Avoids 6+ scattered `jq` calls across `settings.local.json` + `settings.json` (HOME and CWD). | `SETTINGS_CACHE_TTL` |
| Terminal width | 30s | Avoids `/proc/<pid>/stat` walk up 5 ancestors when stdin is a pipe (no controlling TTY). | `WIDTH_CACHE_TTL` |

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

### 2. Terminal width cache

Width detection walks `/proc/<pid>/stat` up to 5 ancestors looking for a parent pts device, because Claude Code does not pass a controlling terminal to statusline scripts. Cached per parent PID for 30s — survives across statusline invocations within a single Claude Code session.

Stale on terminal resize until TTL expires (30s max). Override by setting `TERM_WIDTH=<cols>` in the `statusLine.command` in `settings.json`.

### 3. Git + PR cache (TTL bumped 5s → 60s)

`gh pr view` is the dominant cold-start cost (~1.5s, network). The cache key is the directory hash, so worktrees get independent caches. PR data goes stale 60s but new PRs are rare events.

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
rm -rf /tmp/claude-statusline
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
GIT_CACHE_TTL=60        # bump higher if PR / branch updates feel sluggish
SETTINGS_CACHE_TTL=30   # bump if /effort, /advisor, output-style toggles lag
WIDTH_CACHE_TTL=30      # bump if you rarely resize the terminal
```

Reset all caches: `rm -rf /tmp/claude-statusline`

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
- **Single-pass transcript scan.** `render_thinking_effort` and `render_advisor` each run `tac | grep -m1 | grep -oP | head -1`. Could be merged into one awk pass over the tail. Only matters when transcripts are large and `/effort` / `/advisor` were set in-session.
- **Conditional `gh pr view` skipping.** Detect offline state with a fast `getent hosts github.com` and skip the network call instead of waiting for it to time out. Currently masked by the 60s cache after first hit.
