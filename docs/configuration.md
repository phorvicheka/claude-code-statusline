# Configuration

Day-to-day settings (which sections show, how many lines) live in `~/.claude/statusline.conf`. Reinstalls and plugin
updates replace `~/.claude/statusline.sh` but never touch this file. Don't edit the script's `SHOW_*` lines for
this: an update would undo it.

## Hide or Show Sections

```bash
bash ~/.claude/statusline.sh --hide cost,rate-limits   # comma or space separated
bash ~/.claude/statusline.sh --show cost
bash ~/.claude/statusline.sh --list
bash ~/.claude/statusline.sh --reset
```

With the plugin installed, ask Claude ("hide the cost section of my statusline") or run
`/adaptive-statusline:configure hide cost`. Both run the commands above.

| Section | Hides | Flag in the file |
|---------|-------|------------------|
| `model` | model name | `SHOW_MODEL` |
| `tokens` | context bar and token counts | `SHOW_TOKENS` |
| `git` | branch, dirty state, ahead/behind | `SHOW_GIT` |
| `folder` | folder name on L1 | `SHOW_FOLDER` |
| `thinking` | thinking + effort block | `SHOW_THINKING` |
| `effort` | effort level | `SHOW_EFFORT` |
| `output-style` | output style | `SHOW_OUTPUT_STYLE` |
| `caveman` | caveman mode badge | `SHOW_CAVEMAN` |
| `agent` | agent name | `SHOW_AGENT` |
| `advisor` | advisor model | `SHOW_ADVISOR` |
| `vim-mode` | vim mode | `SHOW_VIM_MODE` |
| `version` | Claude Code version | `SHOW_VERSION` |
| `session-id` | session ID | `SHOW_SESSION_ID` |
| `session-name` | session name | `SHOW_SESSION_NAME` |
| `cost` | cost, duration, lines changed | `SHOW_COST_GROUP` |
| `rate-limits` | 5h / 7d bars | `SHOW_RATE_LIMITS` |
| `worktree` | worktree row | `SHOW_WORKTREE` |
| `pr` | PR / MR badge | `SHOW_PR` |
| `fast` | fast-mode ⚡ badge | `SHOW_FAST` |
| `cache` | prompt-cache badge | `SHOW_CACHE` |
| `spend` | gateway spend meter | `SHOW_SPEND` |
| `cwd-path` | `user@host:path` | `SHOW_CWD_PATH` |
| `clickable-links` | OSC 8 links | `SHOW_CLICKABLE_LINKS` |

## Line Count

```bash
bash ~/.claude/statusline.sh --lines 2   # saved; 1, 2 or 3
STATUSLINE_LINES=1 claude                # one session only; the env var beats the file
```

## The Settings File

`~/.claude/statusline.conf` (move it with `STATUSLINE_CONF=/path`) is plain `KEY=value`:

```
STATUSLINE_LINES=2
SHOW_COST_GROUP=false
```

It is parsed strictly and never executed. Only `SHOW_<known flag>=true|false` and `STATUSLINE_LINES=1|2|3` take
effect; any other line is ignored.

## Advanced Configuration

### Line Layouts

Elements are grouped by line in arrays at the bottom of the script:

```bash
L1=(render_model render_tokens render_git render_folder render_thinking_effort render_agent render_vim)
L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d render_spend render_cache)
# Inside a git worktree:
L3=(render_worktree)
L4=(render_user_host render_output_style render_caveman render_version)
# Otherwise (no worktree) L3 absorbs L4's elements and L4 is empty:
# L3=(render_user_host render_output_style render_caveman render_version)
```

- **L1**: Context (what you're working on) — trimmed so it fits in typical terminal widths without wrapping
- **L2**: Session metadata (cost, limits, IDs)
- **L3**: Worktree details when inside a worktree, otherwise host / output style / version (3-line mode only)
- **L4**: Host / output style / version — only emitted when L3 is showing worktree details (3-line mode only)

### Sizing

```bash
GIT_CACHE_TTL=30        # cache git branch/dirty/ahead-behind (PR data comes from Claude Code's JSON)
GIT_CACHE_TTL_SLOW=300  # same cache for repos under /mnt/* (WSL2 9p), picked automatically
SETTINGS_CACHE_TTL=120  # cache parsed settings.json values (4 files, 6 keys)
WIDTH_CACHE_TTL=300     # fallback width probe only; $COLUMNS (set by Claude Code) is never cached
MAX_BRANCH_LEN=80       # max branch name length (full tier)
TOKEN_BAR_WIDTH=10      # context bar character width
RATE_BAR_WIDTH=10       # rate limit bar character width
THRESHOLD_GREEN=50      # below = green
THRESHOLD_YELLOW=75     # below = yellow, above = red
```

> Render time targets < 200ms warm. Bumping the TTLs trades freshness for CPU.
> See [docs/performance.md](performance.md) for benchmarks and diagnosis.

### Width Tiers

| Tier | Width | Effect |
|------|-------|--------|
| full | >=140 chars | All elements, full labels, branch max 80 chars |
| wide | 100-139 | Smaller bars, branch max 50 chars |
| compact | 76-99 | Compact bars, branch max 30 chars, reset times still shown |
| narrow | <76 | Forces single line, branch max 15 chars, reset times hidden |

Width comes from `TERM_WIDTH` if set, else `$COLUMNS` (Claude Code exports the real terminal size before running the script), else a probe (`tput` / `/dev/tty` / parent-pts walk, cached) for builds that don't set it. `STATUSLINE_DEBUG=1` logs which source was used.

Override: `TERM_WIDTH=150 claude`

### Flex segments

Three segments shrink to fit the row instead of wrapping it: the folder on L1 (`myapp ▸subdir`), the path in `user@host:path ▸subdir`, and the session name in `s-name:`. Only the first flex segment on a row gets the budget (in `STATUSLINE_LINES=1` the folder keeps the static L1 cap, and in 2-line mode the host path is dropped because `s-name:` is the row's flex segment). `assemble_line` renders every other segment first, measures their visible width, and hands the remainder (minus a 6-column margin for double-width emoji) to the flex segment. Rows narrower than the fixed content still overflow; that is a property of the content, not of the flex logic.

### Refresh timer

`install.sh` sets `statusLine.refreshInterval` to 60 (seconds) unless one is already set; `STATUSLINE_REFRESH_INTERVAL=0 bash install.sh -y` skips it. It re-runs the script while Claude Code is idle, which keeps reset countdowns, the prompt-cache TTL and git state current. It does not refresh rate-limit percentages (see [rate-limit-staleness.md](rate-limit-staleness.md)).
