# Claude Code Statusline v2

A multi-line, adaptive-width status line for Claude Code with configurable elements, clickable GitHub links, and color-coded progress bars.

## Features

- **3 display modes**: 1-line (compact), 2-line (default), 3-line (full)
- **Adaptive width**: Gracefully degrades on narrow terminals (full/wide/compact/narrow tiers)
- **Color-coded bars**: Green (<50%) -> Yellow (50-74%) -> Red (>=75%) for context and rate limits
- **Model-colored names**: Amber (Opus), Blue (Sonnet), Cyan (Haiku)
- **Clickable links**: Branch -> GitHub tree URL, Folder -> file:// full path (OSC 8)
- **Git caching**: 10-second cache to avoid slow git operations
- **Fully configurable**: Toggle any element on/off
- **Conditional display**: Elements only appear when data is available
- **Pure bash + jq**: No additional dependencies

### Display Modes

**1-line** (`STATUSLINE_LINES=1`):
```
◆ Opus 4.6 | ████░░░░░░ 48% 96k/1m | ⎇ main ✔ PR#42 ✔ | myapp | ◆ thinking | vim:N | v2.1.97 | s-id:abc123de | cost: $1.23 ~ 12m34s ~ +42/-8
```

**2-line** (`STATUSLINE_LINES=2`, default):
```
◆ Opus 4.6 | ████░░░░░░ 48% 96k/1m | ⎇ main ⚠ ↑2↓1 PR#42 ✔ | myapp | ◆ thinking | agent:review | vim:N | v2.1.97
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d
```

**2-line** (fresh session, minimal data):
```
◆ Opus 4.6 | ░░░░░░░░░░ 0% 0/1.0m | ⎇ feature/my-branch ⚠ | myapp | ◆ thinking | v2.1.97
s-id:536ea9b1 ~ s-name:-- | cost: -- ~ 1s ~ -- | 5h -- | 7d --
```

**2-line** (high usage):
```
◆ Opus 4.6 | ████░░░░░░ 40% 395k/1.0m ⚠ | ⎇ main ✔ | myapp | ◆ thinking | v2.1.97
s-id:1a0230da ~ s-name:improve-coverage | cost: $134.00 ~ 20h35m ~ +8477/-583 | 5h ██░░░░░░░░ 25% ↺~2h54m | 7d █████████░ 91% ↺~21h54m
```

**3-line** (`STATUSLINE_LINES=3`):
```
◆ Opus 4.6 | ████░░░░░░ 48% 96k/1m | ⎇ main ⚠ ↑2↓1 PR#42 ✔ | myapp | ◆ thinking | agent:review | vim:N | v2.1.97
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d
wt: name:feat-auth - path:~/.claude/worktrees/feat-auth - branch:worktree-feat-auth
```

### Elements Reference

#### L1: Identity & Context

| Element | Example | Meaning | Color | Toggle |
|---------|---------|---------|-------|--------|
| Model | `◆ Opus 4.6` | Current Claude model | amber=Opus, blue=Sonnet, cyan=Haiku | `SHOW_MODEL` |
| Context bar | `████░░░░░░ 48%` | Context window used | green <50%, yellow 50-74%, red >=75% | `SHOW_TOKENS` |
| Token counts | `395k/1.0m` | Used tokens / max tokens | magenta / white | `SHOW_TOKENS` |
| Context warning | `⚠` (red) | Total tokens exceed 200k (`exceeds_200k_tokens`) | red | `SHOW_TOKENS` |
| Git branch | `⎇ feature/auth` | Current branch (clickable to GitHub tree) | blue | `SHOW_GIT` |
| Git clean | `✔` | Working tree is clean (no changes) | green | `SHOW_GIT` |
| Git dirty | `⚠` | Working tree has uncommitted changes | yellow | `SHOW_GIT` |
| Ahead | `↑2` | Commits ahead of upstream (hidden when 0) | green | `SHOW_GIT` |
| Behind | `↓1` | Commits behind upstream (hidden when 0) | red | `SHOW_GIT` |
| PR number | `PR#42` | Open PR for this branch (clickable to PR page) | cyan | `SHOW_PR` |
| PR mergeable | `✔` after PR# | PR can be merged (no conflicts) | green | `SHOW_PR` |
| PR conflicting | `✗` after PR# | PR has merge conflicts | red | `SHOW_PR` |
| Folder | `myapp` | Workspace directory basename (clickable to full path) | white | `SHOW_FOLDER` |
| Thinking on | `◆ thinking` | Extended thinking is enabled | magenta | `SHOW_THINKING` |
| Thinking off | `◇ thinking` | Extended thinking is disabled | dim | `SHOW_THINKING` |
| Agent | `agent:review` | Agent name (only when `--agent` active) | dim + magenta | `SHOW_AGENT` |
| Vim mode | `vim:N` / `vim:I` | Current vim mode | green=Normal, yellow=Insert | `SHOW_VIM_MODE` |
| Version | `v2.1.97` | Claude Code version | dim | `SHOW_VERSION` |

#### L2: Session Metadata

| Element | Example | Meaning | Color | Toggle |
|---------|---------|---------|-------|--------|
| Session ID | `s-id:536ea9b1` | First 8 chars of session ID | dim + white | `SHOW_SESSION_ID` |
| Session name | `s-name:my-session` | Custom name (via `--name` or `/rename`), `--` when unset | dim + white | `SHOW_SESSION_NAME` |
| Cost amount | `$1.23` | Session cost in USD, `--` when $0 | dim | `SHOW_COST_GROUP` |
| Duration | `12m34s` | Session wall-clock time, `--` when 0 | white | `SHOW_COST_GROUP` |
| Lines changed | `+42/-8` | Lines added (green) / removed (red), `--` when 0 | green + red | `SHOW_COST_GROUP` |
| 5h rate limit | `5h ███░░░ 38% ↺~2h14m` | 5-hour usage bar + reset countdown, `5h --` when no data | bar color + dim | `SHOW_RATE_LIMITS` |
| 7d rate limit | `7d █░░░░ 18% ↺~4d` | 7-day usage bar + reset countdown, `7d --` when no data | bar color + dim | `SHOW_RATE_LIMITS` |

#### L3: Worktree (3-line mode only)

| Element | Example | Meaning | Color | Toggle |
|---------|---------|---------|-------|--------|
| Worktree name | `wt: name:feat-auth` | Active worktree name | dim + cyan | `SHOW_WORKTREE` |
| Worktree path | `- path:/home/...` | Worktree directory path | dim + white | `SHOW_WORKTREE` |
| Worktree branch | `- branch:wt-feat-auth` | Worktree git branch (clickable) | dim + blue | `SHOW_WORKTREE` |

#### Progress Bar Colors

All progress bars (context, 5h, 7d) use the same color thresholds:

| Range | Color | Meaning |
|-------|-------|---------|
| 0-49% | Green | Safe |
| 50-74% | Yellow | Moderate usage |
| 75-100% | Red | High usage, approaching limit |

#### Separators

| Symbol | Usage |
|--------|-------|
| `\|` | Between element groups |
| `~` | Between related items within a group (e.g., `s-id ~ s-name`, `cost ~ duration ~ lines`) |

#### Placeholder Values

When data is not yet available (e.g., fresh session), elements show `--`:

```
cost: -- ~ 1s ~ --          (no cost yet, has duration, no lines yet)
5h --                        (rate limit data not loaded yet)
7d --                        (rate limit data not loaded yet)
s-name:--                    (no session name set)
```

## Requirements

- **bash** 4.0+
- **jq** (JSON processor)
- **git** (for branch info)
- **gh** (GitHub CLI, optional -- for PR# display)

## Quick Install

```bash
bash install.sh
```

The installer will:
1. Check dependencies
2. Ask you to choose a line count (1, 2, or 3)
3. Back up any existing statusline.sh
4. Install the new script
5. Configure settings.json

## Manual Install

```bash
# 1. Copy the script
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# 2. Add to settings.json (if not already configured)
# {
#   "statusLine": {
#     "type": "command",
#     "command": "bash ~/.claude/statusline.sh"
#   }
# }

# 3. Start a new Claude Code session
```

## Setup with Claude Code (Prompt)

Ask Claude Code to set it up for you. Copy and paste this prompt:

```
I have a statusline package at ~/.claude/statusline-package/ with a README.md.
Please read the README.md first, then:
1. Check and install any missing requirements (bash 4+, jq, git are required; gh CLI is optional for PR# display)
   - On Ubuntu/Debian/WSL: sudo apt install jq git
   - On macOS: brew install jq git
   - gh CLI: https://cli.github.com/
2. Run `bash ~/.claude/statusline-package/install.sh` to install interactively
3. If install.sh fails or you prefer manual setup:
   - Copy ~/.claude/statusline-package/statusline.sh to ~/.claude/statusline.sh and chmod +x it
   - Make sure ~/.claude/settings.json has: {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline.sh"}}
   - Set STATUSLINE_LINES to my preferred line count (1, 2, or 3) at the top of the script
```

## Configuration

Edit the top of `~/.claude/statusline.sh` to customize:

### Line Count

```bash
STATUSLINE_LINES="${STATUSLINE_LINES:-2}"  # 1, 2, or 3
```

Override at runtime: `STATUSLINE_LINES=3 claude`

Or in `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "STATUSLINE_LINES=3 bash ~/.claude/statusline.sh"
  }
}
```

### Feature Toggles

Set any to `false` to hide:

```bash
SHOW_MODEL=true
SHOW_TOKENS=true
SHOW_GIT=true
SHOW_FOLDER=true
SHOW_THINKING=true
SHOW_AGENT=true
SHOW_VIM_MODE=true
SHOW_VERSION=true
SHOW_SESSION_ID=true
SHOW_SESSION_NAME=true
SHOW_COST_GROUP=true
SHOW_RATE_LIMITS=true
SHOW_WORKTREE=true
SHOW_PR=true
SHOW_CLICKABLE_LINKS=true
```

### Line Layouts

Elements are grouped by line in arrays at the bottom of the script:

```bash
L1=(render_model render_tokens render_git render_folder render_thinking render_agent render_vim render_version)
L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d)
L3=(render_worktree)
```

- **L1**: Identity + context (what you're working on)
- **L2**: Session metadata (cost, limits, IDs)
- **L3**: Worktree details (3-line mode only)

### Sizing

```bash
GIT_CACHE_TTL=10        # seconds to cache git status
MAX_BRANCH_LEN=40       # max branch name length
TOKEN_BAR_WIDTH=10      # context bar character width
RATE_BAR_WIDTH=10       # rate limit bar character width
THRESHOLD_GREEN=50      # below = green
THRESHOLD_YELLOW=75     # below = yellow, above = red
```

## Width Tiers

| Tier | Width | Effect |
|------|-------|--------|
| full | >=140 chars | All elements, full labels, max bar widths |
| wide | 100-139 | Smaller bars, branch max 30 chars, rate reset times shown |
| compact | 76-99 | Compact bars, branch max 20 chars |
| narrow | <76 | Forces single line, branch max 12 chars, compact bars |

Override: `TERM_WIDTH=150 claude`

## Clickable Links

- **Branch names**: Link to `https://github.com/{owner}/{repo}/tree/{branch}`
- **PR numbers**: Link to `https://github.com/{owner}/{repo}/pull/{number}`
- **Folder name**: Link to `file://{full_path}` (reveals full CWD on hover/click)
- **Worktree branch**: Same GitHub link format

**Auto-detection**: Links are automatically disabled on terminals that don't support OSC 8 (e.g., WSL conhost.exe). They auto-enable on Windows Terminal (`WT_SESSION`), iTerm2, WezTerm, Kitty, and VS Code.

**Supported terminals**: iTerm2, Kitty, WezTerm, Windows Terminal, VS Code terminal

**Force enable**: `FORCE_HYPERLINK=1 claude`

**Not supported**: WSL default console (`wsl.exe -d Ubuntu`), plain xterm, SSH sessions

**Click**: Cmd+click (macOS) or Ctrl+click (Linux/Windows)

### Known Issue: Clickable Links Not Working

**Status**: Claude Code has a [known bug](https://github.com/anthropics/claude-code/issues/26356) where the Ink renderer strips OSC 8 hyperlink escape sequences during re-rendering. This affects all real terminal emulators (Windows Terminal, iTerm2, Konsole, etc.).

- Links work correctly in IDE terminals (VS Code, Cursor) since v2.1.42
- Links are stripped by Ink before reaching the terminal in standalone mode
- Our escape sequences (`\033]8;;URL\aTEXT\033]8;;\a`) are correct per spec
- A [PTY wrapper workaround](https://github.com/anthropics/claude-code/issues/26356#issuecomment-4094257217) exists but adds Python dependency
- The proper fix requires an upstream change in Claude Code

**What this means**: The link escape codes are in our script and ready to work. Once Anthropic fixes the Ink renderer, clickable links will automatically start working without any changes to this statusline.

**References**:
- [Issue #26356](https://github.com/anthropics/claude-code/issues/26356) -- OSC 8 hyperlinks stripped in real terminals
- [Issue #21586](https://github.com/anthropics/claude-code/issues/21586) -- Original regression (partially fixed for IDE only)
- [OSC 8 spec](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda) -- Terminal hyperlink standard

### Known Limitation: Rate Limit Data Freshness

Rate limit values (5h/7d) update only after each Claude assistant response, not in real-time. They may appear stale when Claude Code is idle compared to Claude Desktop or claude.ai. This is a Claude Code platform limitation, not a bug in this statusline.

See [docs/rate-limit-staleness.md](docs/rate-limit-staleness.md) for full details, alternatives considered, and upstream issue tracking.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Statusline not showing | Check `settings.json` has `statusLine` config. Start a new session. |
| Rate limits show `--` | Rate limit data arrives after first API response. Shows `--` placeholder until then. Requires Pro/Max. |
| Rate limits seem stale | Values update only after each assistant response, not in real-time. See [docs/rate-limit-staleness.md](docs/rate-limit-staleness.md). |
| Unicode blocks show as boxes | Set `LANG=en_US.UTF-8` in your terminal. |
| Branch link not clickable | Auto-disabled on unsupported terminals (WSL conhost). Use Windows Terminal or `FORCE_HYPERLINK=1 claude`. |
| Git info stale | Decrease `GIT_CACHE_TTL` or `rm -rf /tmp/claude-statusline/` |
| Width detection wrong | Override: `TERM_WIDTH=<cols>` in settings.json command. |
| ✔/⚠ not showing | Only appears when CWD is a git repository with cached status. |
| PR# not showing | Requires `gh` CLI installed and authenticated. Hidden when no PR exists for branch. |
| PR ✔/✗ not showing | Merge status requires GitHub to compute mergeability. Shows nothing if status is `UNKNOWN`. |

## Uninstall

```bash
bash uninstall.sh
```

## Adding New Elements

1. Add a `SHOW_*` toggle in the Configuration section
2. Parse the JSON field in the single-jq block
3. Write a `render_*()` function (check `SHOW_*` flag, check data, print or return empty)
4. Add `render_*` to the `L1`/`L2`/`L3` arrays

## References

- [Claude Code Statusline Documentation](https://code.claude.com/docs/en/statusline)
- [isaacaudet/claude-code-statusline](https://github.com/isaacaudet/claude-code-statusline)
- [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)
