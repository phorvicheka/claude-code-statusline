# Configuration

All configuration is done by editing the top of `~/.claude/statusline.sh`.

## Line Count

```bash
STATUSLINE_LINES="${STATUSLINE_LINES:-3}"  # 1, 2, or 3
```

Override at runtime:

```bash
STATUSLINE_LINES=2 claude
```

Or set permanently in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "STATUSLINE_LINES=2 bash ~/.claude/statusline.sh"
  }
}
```

## Feature Toggles

Set any to `false` to hide:

```bash
SHOW_MODEL=true
SHOW_TOKENS=true
SHOW_GIT=true
SHOW_FOLDER=true
SHOW_THINKING=true      # thinking + effort combined block
SHOW_EFFORT=true        # part of thinking+effort block
SHOW_OUTPUT_STYLE=true
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

## Advanced Configuration

### Line Layouts

Elements are grouped by line in arrays at the bottom of the script:

```bash
L1=(render_model render_tokens render_git render_folder render_thinking_effort render_agent render_vim)
L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d)
# Inside a git worktree:
L3=(render_worktree)
L4=(render_user_host render_output_style render_version)
# Otherwise (no worktree) L3 absorbs L4's elements and L4 is empty:
# L3=(render_user_host render_output_style render_version)
```

- **L1**: Context (what you're working on) — trimmed so it fits in typical terminal widths without wrapping
- **L2**: Session metadata (cost, limits, IDs)
- **L3**: Worktree details when inside a worktree, otherwise host / output style / version (3-line mode only)
- **L4**: Host / output style / version — only emitted when L3 is showing worktree details (3-line mode only)

### Sizing

```bash
GIT_CACHE_TTL=5         # seconds to cache git status
MAX_BRANCH_LEN=80       # max branch name length (full tier)
TOKEN_BAR_WIDTH=10      # context bar character width
RATE_BAR_WIDTH=10       # rate limit bar character width
THRESHOLD_GREEN=50      # below = green
THRESHOLD_YELLOW=75     # below = yellow, above = red
```

### Width Tiers

| Tier | Width | Effect |
|------|-------|--------|
| full | >=140 chars | All elements, full labels, branch max 80 chars |
| wide | 100-139 | Smaller bars, branch max 50 chars |
| compact | 76-99 | Compact bars, branch max 30 chars, reset times still shown |
| narrow | <76 | Forces single line, branch max 15 chars, reset times hidden |

Override: `TERM_WIDTH=150 claude`
