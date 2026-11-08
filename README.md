# Claude Code Statusline v2

A multi-line, adaptive-width status line for Claude Code with configurable elements, clickable GitHub links, and color-coded progress bars.

![Claude Code Statusline screenshot](docs/screenshot.png)

<sub>3-line mode at 150 columns, rendered by `statusline.sh` from a sample Claude Code payload.</sub>

## What You Get

- **3 display modes**: 1-line (compact), 2-line, or 3-line (default; grows to 4 rows inside a git worktree; version shown next to model on all modes)
- **Adaptive width**: Gracefully degrades across 4 terminal width tiers
- **Color-coded progress bars**: Context window + rate limits (green/yellow/red)
- **Auto-compact aware**: with `autoCompactWindow` below the model window, the context bar measures against it (`399k/⟲400k · 1.0m max`)
- **Model-colored names**: Amber (Opus), Blue (Sonnet), Cyan (Haiku)
- **Clickable links**: Branch -> GitHub, PR -> PR page, Folder -> full path
- **Git status**: Branch, clean/dirty, ahead/behind, PR/MR number + review state (taken from Claude Code's own JSON: no `gh` CLI, no network)
- **Session info**: Cost, duration, lines changed, rate limits, worktree, prompt-cache warm/cold + TTL, gateway spend limit, fast-mode ⚡ badge
- **Settings group** (`settings:`): Thinking, effort, and advisor grouped on L3 in 3-line mode
- **Output group** (`output:`): Output style and caveman mode grouped on L3 in 3-line mode
- **Cross-platform**: Linux, macOS (stock bash 3.2) and Windows (Git Bash) tested in CI; WSL2 Ubuntu tested locally
- **Pure bash + jq**: No additional dependencies
- **Tested**: `bash tests/run.sh` feeds crafted payloads (xhigh effort, Haiku, legacy shapes, hostile values, worktrees, widths) through the script

## Quick Install

### Plugin Install (Recommended)

In Claude Code:

```
/plugin marketplace add phorvicheka/claude-code-statusline
/plugin install adaptive-statusline@phorvicheka
/adaptive-statusline:install
```

Plugins cannot set `statusLine` themselves, so `/adaptive-statusline:install` runs `install.sh`. It asks for the line
mode, asks before replacing another tool's statusline, and copies the script to `~/.claude/statusline.sh`.
After `/plugin update`, run `/adaptive-statusline:install` again: the installed copy does not update itself.
`/adaptive-statusline:uninstall` removes it.

### Setup via Claude Code Prompt

**Install or update** -- paste this prompt into Claude Code:

```
Please check https://github.com/phorvicheka/claude-code-statusline, read the README.md, and follow the install steps.
```

> **Already have the repo locally?** Use:
> `Please read the README.md in this directory and follow the install steps.`

**Customize elements** -- toggle visibility of any statusline element:

```
In my Claude Code statusline at ~/.claude/statusline.sh, set SHOW_<ELEMENT>=false for: <elements to hide>. Leave all others as true. The toggle flags are at the top of the file.
```

> Example: `...set SHOW_COST_GROUP=false and SHOW_OUTPUT_STYLE=false for: cost group, output style...`
>
> Available elements: `MODEL`, `TOKENS`, `GIT`, `FOLDER`, `THINKING`, `EFFORT`, `OUTPUT_STYLE`, `CAVEMAN`, `AGENT`, `ADVISOR`, `VIM_MODE`, `VERSION`, `SESSION_ID`, `SESSION_NAME`, `COST_GROUP`, `RATE_LIMITS`, `WORKTREE`, `PR`, `FAST`, `CACHE`, `SPEND`, `CWD_PATH`, `CLICKABLE_LINKS`

**Uninstall**:

```
Please check https://github.com/phorvicheka/claude-code-statusline, read the README.md, and run the uninstall steps.
```

> **Already have the repo locally?** Use:
> `Please run bash uninstall.sh in this directory to remove the statusline.`

### Script Install

```bash
cd /path/to/statusline-package
bash install.sh -y     # recommended: non-interactive, 3-line default, auto-update
bash install.sh        # interactive: choose line count, confirm overwrites
bash install.sh -y -l 2  # non-interactive, 2-line mode
```

The installer will:
1. Check dependencies (bash 3.2+, jq, git)
2. Back up any existing statusline.sh
3. Install or update the script to `~/.claude/statusline.sh`
4. Configure `~/.claude/settings.json`

### Manual Install

```bash
# 1. Copy the script (from the project directory)
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# 2. Configure settings.json
# Add or merge into ~/.claude/settings.json:
# {
#   "statusLine": {
#     "type": "command",
#     "command": "bash ~/.claude/statusline.sh"
#   }
# }

# 3. Start a new Claude Code session
```

### Requirements

- **Claude Code CLI** running in a terminal. See [Where It Works](#where-it-works).
- **bash** 3.2+ (stock macOS `/bin/bash` works; on Windows, Git Bash)
- **jq** (JSON processor)
- **git** (for branch info)

The PR badge comes from Claude Code's own JSON, so `gh` is not needed.

### Where It Works

The status line is a feature of the Claude Code **CLI in a terminal**. That includes the integrated terminal of
VS Code, Cursor or JetBrains IDEs, where the JetBrains plugin also runs `claude`. The Claude Code docs do not
document `statusLine` for the VS Code extension's chat panel, the Desktop app, or claude.ai/code (web, no local
`~/.claude`), so those are not supported.

The plugin install was tested on Claude Code 2.1.319. Older versions without plugin support can use the script install.

### Platform Notes

Every push and PR runs `tests/ci.sh` on all three OSes ([workflow](.github/workflows/test.yml)): shellcheck,
`bash -n`, and `tests/run.sh`, which feeds crafted Claude Code JSON through the scripts. Run the same check locally
with `bash tests/ci.sh --fresh`. CI tests the scripts, not a live Claude Code session on each OS. On Windows, 3
symlink and POSIX-mode cases are skipped, because Git Bash has neither.

| Platform | Status | Tested by | Notes |
|----------|--------|-----------|-------|
| Linux | Tested (CI) | CI `ubuntu-latest` | Native environment |
| WSL (Ubuntu) | Tested locally | `tests/ci.sh` on WSL2 Ubuntu | Handles Windows backslash paths (`C:\Users\...`) sent by Claude Code |
| macOS | Tested (CI) | CI `macos-latest`, stock `/bin/bash` 3.2 | BSD `date`/`stat`/`grep`, `tail -r` instead of `tac` |
| Windows | Tested (CI) | CI `windows-latest`, Git Bash | Requires [Git for Windows](https://gitforwindows.org/): Claude Code runs status line commands through Git Bash, and falls back to PowerShell without it, which cannot run this script. The installer writes a `C:/Users/...` path. `stty size` may fail (defaults to 80 cols / compact tier) |

Claude Code may send working directory paths with backslashes on Windows. The statusline normalizes all path separators automatically -- folder names, git operations, and settings lookups all work regardless of separator style.

> **Tip: multiple package managers on WSL/Windows.** If you installed Claude Code with both npm and pnpm (or yarn), your shell may resolve `claude` to the older installation. Run `which claude` to see which binary is active, then update with that package manager. The statusline's version display reflects whatever binary is running -- if it looks outdated, this is likely why.

## Configuration

See [Configuration Guide](docs/configuration.md) for line count, feature toggles, sizing, and width tiers.

## Statusline Anatomy

See [Statusline Anatomy](docs/anatomy.md) for display modes, element reference, thinking/effort details, and progress bar colors.

## Performance

Render time targets **< 200ms warm**. Caches git state (30s; 300s on WSL2 `/mnt/*`), the `settings.json` parse (120s), the transcript scan for `/advisor` (incremental), and a fallback `TERM_WIDTH` probe in a private per-user cache dir (`$XDG_RUNTIME_DIR/claude-statusline/`, else `/tmp/claude-statusline-$UID/`, mode 0700). See [docs/performance.md](docs/performance.md) for benchmarks, diagnosis, and TUI redraw stacking explained.

## Known Limitations

See [Known Limitations](docs/known-limitations.md) for clickable link support, rate limit data freshness, and the auto-compact limit.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Statusline not showing | Check `settings.json` has `statusLine` config. Start a new session. |
| Version shows outdated | If you installed Claude Code with multiple package managers (npm, pnpm, yarn), only one is on your `$PATH`. Update the one your shell actually resolves: run `which claude` to find it, then update with the matching package manager (e.g. `pnpm update -g @anthropic-ai/claude-code`). |
| Folder shows raw path instead of name | Fixed in v2. The statusline normalizes Windows backslash paths (`C:\Users\...`) automatically. Update to the latest version. |
| Rate limit reset time not showing | Fixed in v2. Reset times (`↺~2h14m`) now parse both ISO 8601 strings and unix timestamps. Also shown at compact width (76-99 cols) -- previously only at full/wide (>=100). On Git Bash, `stty size` may fail, defaulting to 80 cols (compact). Update to the latest version. |
| Rate limits show `--` | Rate limit data arrives after first API response. Shows `--` until then. Requires Pro/Max. |
| Rate limits seem stale | Values update only after each assistant response. See [docs/rate-limit-staleness.md](docs/rate-limit-staleness.md). |
| Unicode blocks show as boxes | Set `LANG=en_US.UTF-8` in your terminal. |
| Branch link not clickable | Auto-disabled on unsupported terminals. Use Windows Terminal or `FORCE_HYPERLINK=1 claude`. |
| Git info stale | Decrease `GIT_CACHE_TTL` (default 30s) or `rm -rf "$XDG_RUNTIME_DIR/claude-statusline" "/tmp/claude-statusline-$(id -u)"` |
| Statusline + input box duplicated above output | TUI redraw stacking when render > ~300ms. See [docs/performance.md](docs/performance.md). The script targets < 200ms warm; if yours is slower, profile with `STATUSLINE_DEBUG=1` and bump TTLs. |
| Output style / advisor setting slow to reflect | Settings preload is cached (`SETTINGS_CACHE_TTL`, default 120s). `rm -rf "$XDG_RUNTIME_DIR/claude-statusline" "/tmp/claude-statusline-$(id -u)"` to refresh. Effort and thinking are live: they come straight from Claude Code's JSON. |
| Wrong width after terminal resize | Claude Code passes the live size in `$COLUMNS`, which is used first and never cached. Only the fallback probe (builds that don't set `COLUMNS`) is cached (`WIDTH_CACHE_TTL`); `rm -rf "$XDG_RUNTIME_DIR/claude-statusline" "/tmp/claude-statusline-$(id -u)"` to refresh. |
| Branch name truncated | Width detection may fail on Git Bash (now uses `tput cols` with 120-col default). Update to latest, or override: `TERM_WIDTH=<cols>` in settings.json command. |
| Width detection wrong | Override: `TERM_WIDTH=<cols>` in settings.json command. |
| PR# not showing | Comes from Claude Code's `pr.*` JSON (shown only while an open PR/MR exists for the branch; GitLab MRs need Claude Code >= 2.1.234). The `gh` CLI is no longer used. |
| Thinking not updating on `meta+t` | In-memory only -- not written to disk. Use `/config` to toggle persistently. |
| Effort level not showing | Effort is read from `effort.level` in Claude Code's JSON, which is absent when the active model has no effort parameter (e.g. Haiku), so the statusline then shows no effort on purpose. For other models set it with `/effort <level>`: `low`, `medium`, `high`, `xhigh`, `max`. |
| Effort level stuck | `CLAUDE_CODE_EFFORT_LEVEL` (env or `settings.json` `env` block) overrides `/effort` inside Claude Code itself; remove it. The statusline just mirrors what Claude Code reports. |
| Output style not showing | Reads from JSON input. Ensure Claude Code v2.1+ and start a fresh session. |
| Something else looks wrong | Set `STATUSLINE_DEBUG=1` in your env to log raw JSON to `~/.claude/statusline-debug.log`. See [Debugging Guide](docs/debugging.md). |

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Uninstall

```bash
bash uninstall.sh
```

## Contributing

See [Contributing: Adding New Elements](docs/contributing.md). Run `bash tests/run.sh` before committing.

## References

- [Claude Code Statusline Documentation](https://code.claude.com/docs/en/statusline)
- [isaacaudet/claude-code-statusline](https://github.com/isaacaudet/claude-code-statusline)
- [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)

## License

MIT. See [LICENSE](LICENSE).
