# WSL2 + Cursor / VS Code Troubleshooting

Real-world fix log for users running Claude Code from a **Cursor** or **VS Code** integrated terminal under **WSL2** with the project on a `/mnt/*` (NTFS via 9p) host. This is the worst-case environment for statusline performance and terminal scrollback retention.

If you see **both** of these symptoms, this doc is for you:

- Statusline + input box duplicated above streaming output (`❯` prompts piling up)
- Cannot scroll back to earlier output in the same Claude Code session — history feels cut off

## TL;DR

| Layer | Default | Problem | Fix |
|-------|---------|---------|-----|
| Statusline `GIT_CACHE_TTL` | 60s | Warm renders 300–700ms on WSL2 /mnt/* → frames stack in scrollback | Bump to **300s** |
| Statusline `SETTINGS_CACHE_TTL` | 30s | Re-parsing 4 settings files every 30s adds fork tax | Bump to **120s** |
| Statusline `WIDTH_CACHE_TTL` | 30s | `/proc` walk on every other render | Bump to **300s** |
| Cursor `terminal.integrated.scrollback` | 1000 lines | Stacked statusline frames burn buffer fast → old output evicted | Bump to **50000** |

After both fixes: warm render ~220ms (was 567–695ms), scrollback retains full session.

## Why WSL2 + `/mnt/*` is the worst case

Two slowdowns compound:

1. **WSL2 `fork()` tax.** Each statusline render forks ~14 subshells (one per renderer in `assemble_line`). On WSL2 each fork costs ~10–30ms vs ~1ms on native Linux. Baseline ~210ms before any I/O.
2. **`/mnt/*` 9p protocol.** Windows NTFS volumes are exposed to WSL2 over Plan 9 protocol. Every `git status`, `git rev-parse`, `gh pr view` traverses this bridge. Order of magnitude slower than native ext4. A small repo with 2 commits still pays the per-syscall overhead.

The script targets <200ms warm. On WSL2 + `/mnt/*` with default TTLs you sit at 300–700ms — past the [TUI redraw budget](performance.md#why-this-matters-tui-redraw-stacking) of ~300ms — and Claude Code stacks duplicate frames in scrollback instead of overwriting in place.

## Fix 1 — Bump statusline TTLs

Edit `~/.claude/statusline.sh` (or `~/.claude/statusline-package/statusline.sh` + re-run `install.sh -y`):

```bash
# ── Sizing ──
GIT_CACHE_TTL=300       # was 60
SETTINGS_CACHE_TTL=120  # was 30
WIDTH_CACHE_TTL=300     # was 30
```

Cache invalidation behaviour:

- Branch / dirty / PR data stays accurate inside the 5-minute window because you rarely cut new PRs that fast.
- `/effort`, `/advisor`, output style toggles take up to 2 min to reflect. Lower `SETTINGS_CACHE_TTL` if that bothers you (cost ~10–20ms per render).
- Terminal resizes take up to 5 min to re-detect width. Lower `WIDTH_CACHE_TTL` if you resize often, or set `TERM_WIDTH=<cols>` in your `settings.json` `statusLine.command` to skip detection entirely.

Reset cache to force fresh values: `rm -rf /tmp/claude-statusline/`

### Verify

```bash
cat > /tmp/sl-test.json <<EOF
{"session_id":"test","transcript_path":"","cwd":"$(pwd)","model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"workspace":{"current_dir":"$(pwd)","project_dir":"$(pwd)"},"version":"2.1.119","output_style":{"name":"default"},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_lines_added":0,"total_lines_removed":0}}
EOF

rm -rf /tmp/claude-statusline
time bash ~/.claude/statusline.sh < /tmp/sl-test.json > /dev/null   # cold
time bash ~/.claude/statusline.sh < /tmp/sl-test.json > /dev/null   # warm
time bash ~/.claude/statusline.sh < /tmp/sl-test.json > /dev/null   # warm
time bash ~/.claude/statusline.sh < /tmp/sl-test.json > /dev/null   # warm
```

Targets: warm <300ms, ideally <200ms. Should be flat across runs (not climbing).

### Empirical results on WSL2 + `/mnt/e/` (NTFS)

Same project, same machine, same Cursor integrated terminal:

| Run | Before bump | After bump |
|-----|-------------|------------|
| Cold | ~2s | ~2s (network-bound) |
| Warm 1 | 321ms | 251ms |
| Warm 2 | 352ms | 217ms |
| Warm 3 | 567ms | 216ms |
| Warm 4 | 695ms | 225ms |

Before: climbing past 600ms → TUI stacking inevitable. After: flat ~220ms → well inside redraw budget.

## Fix 2 — Bump Cursor / VS Code terminal scrollback

Even with the statusline fix, if you experienced the stacking before patching, your scrollback is likely already capped.

**Cursor / VS Code default**: `terminal.integrated.scrollback = 1000` lines.

A single long Claude turn can emit thousands of lines (tool calls, file diffs, agent output). 1000 lines evicts within minutes.

Edit your user settings:

- **Cursor**: `%APPDATA%\Cursor\User\settings.json` (Windows) or `~/.config/Cursor/User/settings.json` (Linux/macOS)
- **VS Code**: same path with `Code` instead of `Cursor`

Add:

```json
{
  "terminal.integrated.scrollback": 50000,
  "terminal.integrated.fastScrollSensitivity": 5,
  "terminal.integrated.mouseWheelScrollSensitivity": 1
}
```

- `scrollback: 50000` — 50× default. ~20 MB RAM per terminal pane worst case.
- `fastScrollSensitivity: 5` — Alt+wheel jumps faster through long output.
- `mouseWheelScrollSensitivity: 1` — normal wheel smoother.

**Apply**: Cursor reads `settings.json` live, but existing terminal panes keep their old buffer size. Either:

- Kill all panes (Ctrl+Shift+P → "Terminal: Kill All Terminals") and open a fresh one, or
- Restart Cursor

## Detecting your terminal

If unsure whether Claude Code is running inside Cursor / VS Code:

```bash
echo "TERM_PROGRAM=$TERM_PROGRAM"   # 'vscode' means Cursor or VS Code
echo "TERM=$TERM"                   # usually 'xterm-256color'
```

Or walk the process tree from `claude` up to the GUI process — on Windows you'll see `claude.exe → bash.exe → ... → Cursor.exe` or `Code.exe`.

## Mouse-wheel scroll captured by TUI

If `Shift+ScrollWheel` works but plain `ScrollWheel` does not, Claude Code's TUI is capturing mouse events. This is independent of the scrollback size and is upstream behaviour. Workarounds:

- Always use `Shift+ScrollWheel` to bypass mouse capture
- Use PageUp / PageDown / Ctrl+Home / Ctrl+End — VS Code-style keyboard scrolling

## Still seeing stacking?

After both fixes, if duplicate frames return:

1. Confirm the new statusline is the one running: `grep '^GIT_CACHE_TTL=' ~/.claude/statusline.sh` should print `300`.
2. Start a **new** Claude Code session — the previous session loaded the old binary.
3. Reduce `STATUSLINE_LINES` (`STATUSLINE_LINES=2 claude` or `=1`).
4. `Ctrl+L` clears scrollback between long turns.
5. Move the project to native WSL ext4 (`~/projects/...`) instead of `/mnt/*`. Largest single win — eliminates the 9p tax entirely.
6. Try a non-VS-Code terminal: WezTerm, Alacritty, Kitty. Redraw better than xterm.js under WSL2.

See also [performance.md](performance.md) for the underlying stacking mechanism and [debugging.md](debugging.md) for `STATUSLINE_DEBUG=1` profiling.

## References

- [Performance benchmarks and cache layout](performance.md)
- [Known limitations (clickable links, rate-limit staleness)](known-limitations.md)
- WSL2 9p protocol overhead: <https://learn.microsoft.com/en-us/windows/wsl/filesystems>
- VS Code terminal scrollback: <https://code.visualstudio.com/docs/terminal/basics#_scrollback>
