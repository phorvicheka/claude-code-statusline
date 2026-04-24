# Statusline Anatomy

## Display Modes

**1-line** (`STATUSLINE_LINES=1`):
```
◆ Opus 4.6 | ████░░░░░░ 48% 96k/1m | ⎇ main ✔  ~ PR #42 ✔ | myapp | 🧠  ◆ thinking ~ ◕ high | 🔎  explanatory | vim:N | v2.1.97 | s-id:abc123de | cost: $1.23 ~ 12m34s ~ +42/-8
```

**2-line** (`STATUSLINE_LINES=2`):
```
◆ Opus 4.6 | ████░░░░░░ 48% 96k/1m | ⎇ main 🛠️  ↑2↓1  ~ PR #42 ✔ | myapp | 🧠  ◇ thinking ~ ◎ auto | agent:review | vim:N
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d | user@host | ⚙️  default | v2.1.97
```

**3-line** (`STATUSLINE_LINES=3`, default) — no worktree:
```
◆ Opus 4.6 | ████░░░░░░ 48% 96k/1m | ⎇ main 🛠️  ↑2↓1  ~ PR #42 ✔ | myapp | 🧠  ◆ thinking ~ ◕ high | agent:review | vim:N
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d
user@host | 🎓  learning | v2.1.97
```

**3-line** (`STATUSLINE_LINES=3`, default) — inside a git worktree (L3 + L4):
```
◆ Opus 4.6 | ████░░░░░░ 48% 96k/1m | ⎇ main 🛠️  ↑2↓1  ~ PR #42 ✔ | myapp | 🧠  ◆ thinking ~ ◕ high | agent:review | vim:N
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d
wt: name:feat-auth - path:~/.claude/worktrees/feat-auth - branch:worktree-feat-auth
user@host | 🎓  learning | v2.1.97
```

**Fresh session** (minimal data, 3-line default):
```
◆ Opus 4.6 | ░░░░░░░░░░ 0% 0/1.0m | ⎇ feature/my-branch 🛠️ | myapp | 🧠  ◇ thinking ~ ◎ auto
s-id:536ea9b1 ~ s-name:-- | cost: -- ~ 1s ~ -- | 5h -- | 7d --
user@host | ⚙️  default | v2.1.97
```

**High usage** (3-line default):
```
◆ Opus 4.6 | ████░░░░░░ 40% 395k/1.0m ⚠️ | ⎇ main ✔ | myapp | 🧠  ◆ thinking ~ ● max
s-id:1a0230da ~ s-name:improve-coverage | cost: $134.00 ~ 20h35m ~ +8477/-583 | 5h ██░░░░░░░░ 25% ↺~2h54m | 7d █████████░ 91% ↺~21h54m
user@host | ⚙️  default | v2.1.97
```

## Elements Reference

### L1: Identity & Context

| Element | Example | Meaning | Color | Toggle |
|---------|---------|---------|-------|--------|
| Model | `◆ Opus 4.6` | Current Claude model | amber=Opus, blue=Sonnet, cyan=Haiku | `SHOW_MODEL` |
| Context bar | `████░░░░░░ 48%` | Context window used | green <50%, yellow 50-74%, red >=75% | `SHOW_TOKENS` |
| Token counts | `395k/1.0m` | Used / max tokens | white / dim | `SHOW_TOKENS` |
| Context warning | `⚠️` | Exceeds 200k tokens | red | `SHOW_TOKENS` |
| Git branch | `⎇ feature/auth` | Current branch (clickable) | blue | `SHOW_GIT` |
| Git status | `✔` / `🛠️` | Clean / dirty working tree | green / yellow | `SHOW_GIT` |
| Ahead/Behind | `↑2` `↓1` | Commits ahead/behind upstream | green / red | `SHOW_GIT` |
| PR | `PR #42 ✔` | PR number + merge status (clickable) | dim + yellow | `SHOW_PR` |
| Folder | `myapp` | Workspace basename (clickable) | white | `SHOW_FOLDER` |
| Thinking + Effort | `🧠  ◆ thinking ~ ◕ high` | Thinking state + effort level | see below | `SHOW_THINKING` / `SHOW_EFFORT` |
| Agent | `agent:review` | Active agent name | dim + magenta | `SHOW_AGENT` |
| Advisor | `advisor:opus` | Advisor model (`/advisor [opus\|sonnet\|off]`) | amber=Opus, blue=Sonnet, cyan=Haiku | `SHOW_ADVISOR` |
| Vim mode | `vim:N` | Current vim mode | green=N, yellow=I | `SHOW_VIM_MODE` |

### L2: Session Metadata

| Element | Example | Meaning | Toggle |
|---------|---------|---------|--------|
| Session ID | `s-id:536ea9b1` | First 8 chars of session ID | `SHOW_SESSION_ID` |
| Session name | `s-name:my-session` | Custom name (`--` if unset) | `SHOW_SESSION_NAME` |
| Cost | `$1.23` | Session cost (`--` if $0) | `SHOW_COST_GROUP` |
| Duration | `12m34s` | Wall-clock time | `SHOW_COST_GROUP` |
| Lines changed | `+42/-8` | Added (green) / removed (red) | `SHOW_COST_GROUP` |
| 5h rate limit | `5h ███░░░ 38% ↺~2h14m` | 5-hour usage + reset countdown | `SHOW_RATE_LIMITS` |
| 7d rate limit | `7d █░░░░ 18% ↺~4d` | 7-day usage + reset countdown | `SHOW_RATE_LIMITS` |

### L3: Worktree or Host Row (3-line mode only)

When you're inside a git worktree, L3 renders worktree details and the host/style/version row is pushed to L4. When you're not in a worktree, L3 renders the host/style/version row directly (L4 is empty).

| Element | Example | Toggle |
|---------|---------|--------|
| Worktree name | `wt: name:feat-auth` | `SHOW_WORKTREE` |
| Worktree path | `- path:/home/...` | `SHOW_WORKTREE` |
| Worktree branch | `- branch:wt-feat-auth` (clickable) | `SHOW_WORKTREE` |
| User@host | `phorvicheka@DESKTOP-NVB94AN` | (always shown) |
| Output style | `⚙️  default` | `SHOW_OUTPUT_STYLE` |
| Caveman mode | `◕  caveman` / `●  caveman:ultra` | `SHOW_CAVEMAN` |
| Version | `v2.1.113` | `SHOW_VERSION` |

### L4: Host Row (3-line mode, only when L3 is worktree)

| Element | Example | Toggle |
|---------|---------|--------|
| User@host | `phorvicheka@DESKTOP-NVB94AN` | (always shown) |
| Output style | `⚙️  default` | `SHOW_OUTPUT_STYLE` |
| Caveman mode | `◕  caveman` / `●  caveman:ultra` | `SHOW_CAVEMAN` |
| Version | `v2.1.113` | `SHOW_VERSION` |

### Caveman Mode Icons

| Mode | Icon | Label |
|------|------|-------|
| `lite` | ◔ | `caveman:lite` |
| `full` (default) | ◕ | `caveman` |
| `ultra` | ● | `caveman:ultra` |
| `wenyan-lite` | ◔ 文 | `caveman:wenyan-lite` |
| `wenyan` / `wenyan-full` | ◕ 文 | `caveman:wenyan` |
| `wenyan-ultra` | ● 文 | `caveman:wenyan-ultra` |
| `commit` | ✍️ | `caveman:commit` |
| `review` | ⊙ | `caveman:review` |

## Thinking & Effort

Rendered as a combined block: `🧠  ◆ thinking ~ ◕ high`

**Thinking state** -- `◆` (on) / `◇` (off):

Read from (in priority order):
1. `is_thinking` in statusline JSON input (future Claude Code support)
2. `alwaysThinkingEnabled` in `.claude/settings.local.json` (project)
3. `alwaysThinkingEnabled` in `~/.claude/settings.local.json` (global)
4. `alwaysThinkingEnabled` in `.claude/settings.json` (project)
5. `alwaysThinkingEnabled` in `~/.claude/settings.json` (global)

> **Note:** `meta+t` toggles thinking in-memory only (not written to disk). Use `/config` to toggle persistently.

**Effort level** -- read from (in priority order):
1. `effort_level` / `effortLevel` / `effort` in statusline JSON (future-proof: not yet in schema)
2. Transcript JSONL -- scans backward for the most recent `/effort` command output (catches session-only levels like `max`)
3. `effortLevel` key in settings JSON (written by `/effort` for persistable levels)
4. `CLAUDE_CODE_EFFORT_LEVEL` environment variable (runtime)
5. `env.CLAUDE_CODE_EFFORT_LEVEL` in settings JSON `env` blocks

| Value | Icon | Note |
|-------|------|------|
| absent / `auto` | `◎` | Default -- Claude chooses (equivalent to `high`) |
| `low` | `◔` | Quick, minimal overhead |
| `medium` | `◑` | Balanced |
| `high` | `◕` | Thorough |
| `xhigh` | `◉` | Extra-high reasoning budget |
| `max` | `●` | Maximum effort (session-only -- not written to settings.json) |

Set via `/effort <level>` or `/config`. Setting to `auto` removes the key from settings entirely.

> **Note:** `/effort max` is session-only and does not persist to `settings.json`. The statusline detects it by parsing the transcript JSONL file. Avoid setting `CLAUDE_CODE_EFFORT_LEVEL` in `settings.json` `env` block — it overrides `/effort` at runtime.

## Output Style

Reads from `output_style.name` in statusline JSON, falling back to `outputStyle` in `settings.local.json`.

| Style | Icon | Set via |
|-------|------|---------|
| `default` | `⚙️` | `/config` or absent |
| `explanatory` | `🔎` | `/config` |
| `learning` | `🎓` | `/config` |

## Separators & Placeholders

| Symbol | Usage |
|--------|-------|
| `\|` | Between element groups |
| `~` | Between related items within a group |
| `--` | Data not yet available (e.g., fresh session) |

## Progress Bar Colors

All bars (context, 5h, 7d) use the same thresholds:

| Range | Color | Meaning |
|-------|-------|---------|
| 0-49% | Green | Safe |
| 50-74% | Yellow | Moderate usage |
| 75-100% | Red | High usage |
