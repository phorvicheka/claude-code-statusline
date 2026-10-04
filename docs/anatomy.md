# Statusline Anatomy

## Display Modes

**1-line** (`STATUSLINE_LINES=1`):
```
user@host | ◆ Opus 4.6 ~ v2.1.97 | ████░░░░░░ 48% 96k/1m | ⎇ main ✔  ~ PR #42 ✔ | myapp | settings: 🧠  ◆ thinking ~ ◕ high ~ advisor:opus | output: 🔎  explanatory | agent:review | vim:N | s-id:abc123de | cost: $1.23 ~ 12m34s ~ +42/-8
```

**2-line** (`STATUSLINE_LINES=2`):
```
◆ Opus 4.6 ~ v2.1.97 | ████░░░░░░ 48% 96k/1m | ⎇ main 🛠️  ↑2↓1  ~ PR #42 ✔ | myapp | agent:review | vim:N
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d | user@host | settings: 🧠  ◇ thinking ~ ◎ auto ~ advisor:opus | output: ⚙️  default
```

**3-line** (`STATUSLINE_LINES=3`, default) — no worktree:
```
◆ Opus 4.6 ~ v2.1.97 | ████░░░░░░ 48% 96k/1m | ⎇ main 🛠️  ↑2↓1  ~ PR #42 ✔ | myapp | agent:review | vim:N
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d
user@host | settings: 🧠  ◆ thinking ~ ◕ high ~ advisor:opus | output: 🎓  learning ~ ◕  caveman
```

**3-line** (`STATUSLINE_LINES=3`, default) — inside a git worktree (L3 + L4):
```
◆ Opus 4.6 ~ v2.1.97 | ████░░░░░░ 48% 96k/1m | ⎇ main 🛠️  ↑2↓1  ~ PR #42 ✔ | myapp | agent:review | vim:N
s-id:abc123de ~ s-name:my-session | cost: $1.23 ~ 12m34s ~ +42/-8 | 5h ███░░░░░░░ 38% ↺~2h14m | 7d █░░░░░░░░░ 18% ↺~4d
wt: name:feat-auth - path:/home/user/projects/.git/worktrees/feat-auth
user@host | settings: 🧠  ◆ thinking ~ ◕ high ~ advisor:opus | output: 🎓  learning ~ ◕  caveman
```

(Branch omitted when it matches L1 git branch; shown only on different branches)

**Fresh session** (minimal data, 3-line default):
```
◆ Opus 4.6 ~ v2.1.97 | ░░░░░░░░░░ 0% 0/1.0m | ⎇ feature/my-branch 🛠️ | myapp
s-id:536ea9b1 ~ s-name:-- | cost: -- ~ 1s ~ -- | 5h -- | 7d --
user@host | settings: 🧠  ◇ thinking ~ ◎ auto | output: ⚙️  default
```

**High usage** (3-line default):
```
◆ Opus 4.6 ~ v2.1.97 | ████░░░░░░ 40% 395k/1.0m ⚠️ | ⎇ main ✔ | myapp
s-id:1a0230da ~ s-name:improve-coverage | cost: $134.00 ~ 20h35m ~ +8477/-583 | 5h ██░░░░░░░░ 25% ↺~2h54m | 7d █████████░ 91% ↺~21h54m
user@host | settings: 🧠  ◆ thinking ~ ● max | output: ⚙️  default
```

## Elements Reference

### L1: Identity & Context

| Element | Example | Meaning | Color | Toggle |
|---------|---------|---------|-------|--------|
| Model | `◆ Opus 4.6 ~ v2.1.97` | Current Claude model + version | amber=Opus, blue=Sonnet, cyan=Haiku | `SHOW_MODEL` / `SHOW_VERSION` |
| Context bar | `████░░░░░░ 48%` | Context window used | green <50%, yellow 50-74%, red >=75% | `SHOW_TOKENS` |
| Token counts | `395k/1.0m` | Used / max tokens | white / dim | `SHOW_TOKENS` |
| Context warning | `⚠️` | Exceeds 200k tokens | red | `SHOW_TOKENS` |
| Git branch | `⎇ feature/auth` | Current branch (clickable) | blue | `SHOW_GIT` |
| Git status | `✔` / `🛠️` | Clean / dirty working tree | green / yellow | `SHOW_GIT` |
| Ahead/Behind | `↑2` `↓1` | Commits ahead/behind upstream | green / red | `SHOW_GIT` |
| PR / MR | `PR #42 ✔` | Number + review state from `pr.*` JSON (clickable). `✔` approved, `✗` changes requested, `draft`, `…` pending. GitLab shows `MR #n` | dim + yellow | `SHOW_PR` |
| Fast mode | `⚡` | Fast mode is on (`fast_mode`) | yellow | `SHOW_FAST` |
| Folder | `myapp` | Workspace basename (clickable) | white | `SHOW_FOLDER` |
| Agent | `agent:review` | Active agent name (when active) | dim + magenta | `SHOW_AGENT` |
| Vim mode | `vim:N` | Current vim mode (when active): `N` normal, `I` insert, `V` visual, `VL` visual line | green=N, yellow=I, magenta=V/VL | `SHOW_VIM_MODE` |

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
| Spend limit | `spend ███░░ 24% ↺~3d $12.5/$50` | Gateway spend limit (`rate_limits.spend_limit`). Only appears behind a Claude apps gateway with spend limits | `SHOW_SPEND` |
| Prompt cache | `cache: 97% ↺~4m` / `cache: cold` | Warm: session hit ratio + time until the cache goes cold. Cold: next request re-caches. Full tier (>=140 cols) only; hidden if the session reports no caching | `SHOW_CACHE` |

### L3: Worktree or Host Row (3-line mode only)

When you're inside a git worktree, L3 renders worktree details and the host/settings/output row is pushed to L4. When you're not in a worktree, L3 renders the host/settings/output row directly (L4 is empty).

| Element | Example | Toggle |
|---------|---------|--------|
| Worktree name | `wt: name:feat-auth` | `SHOW_WORKTREE` |
| Worktree path | `- path:/home/user/.../feat-auth` (full width) | `SHOW_WORKTREE` |
| Worktree branch | `- branch:wt-feat-auth` (shown only if different from L1 branch, clickable) | `SHOW_WORKTREE` |
| User@host:cwd | `phorvicheka@DESKTOP-NVB94AN:~/projects/api` | Host, plus the PS1-style working directory. The path is left-truncated (`…/tail`) to fit the row, hidden when there is no room, and hidden when the worktree row already shows the same path | `SHOW_CWD_PATH` |
| Settings group | `settings: 🧠  ◆ thinking ~ ◕ high ~ advisor:opus` | `SHOW_THINKING` / `SHOW_EFFORT` / `SHOW_ADVISOR` |
| Output group | `output: ⚙️  default ~ ◕  caveman` | `SHOW_OUTPUT_STYLE` / `SHOW_CAVEMAN` |

### L4: Host Row (3-line mode, only when L3 is worktree)

| Element | Example | Toggle |
|---------|---------|--------|
| User@host:cwd | `phorvicheka@DESKTOP-NVB94AN` | Same element as above; the cwd part is dropped here because the worktree row already prints it | `SHOW_CWD_PATH` |
| Settings group | `settings: 🧠  ◆ thinking ~ ◕ high ~ advisor:opus` | `SHOW_THINKING` / `SHOW_EFFORT` / `SHOW_ADVISOR` |
| Output group | `output: ⚙️  default ~ ◕  caveman` | `SHOW_OUTPUT_STYLE` / `SHOW_CAVEMAN` |

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

Rendered as part of the `settings:` group on L3 (3-line mode) or as standalone elements on 1-line/2-line modes: `settings: 🧠  ◆ thinking ~ ◕ high ~ advisor:opus`

Claude Code sends both as **objects** in the statusline JSON: `thinking: {"enabled": true}` and `effort: {"level": "xhigh"}`. (Older versions of this script read them as scalars, which made thinking always render off and dropped the effort level; see `tests/run.sh`.) Scalar forms from older Claude Code builds are still accepted.

**Thinking state** -- `◆` (on) / `◇` (off), read from (first present wins):
1. `thinking.enabled` in the statusline JSON (live; `meta+t` toggles show immediately)
2. `alwaysThinkingEnabled` in `.claude/settings.local.json`, `~/.claude/settings.local.json`, `.claude/settings.json`, `~/.claude/settings.json` (only when the JSON has no thinking field)

**Effort level**:
1. `effort.level` in the statusline JSON. This is the live session value: it includes mid-session `/effort` changes, session-only levels such as `max`, per-model saved levels (`modelSettings.<model>.effortLevel`) and the model's own default. Nothing else is consulted.
2. JSON from a current Claude Code **without** an `effort` key means the active model has no effort parameter (e.g. Haiku). The statusline then shows no effort (instead of guessing `auto`/`high`).
3. Only for payloads from older Claude Code (no `thinking` / `fast_mode` fields at all): transcript `/effort` output, then `modelSettings.<model-id>.effortLevel`, then top-level `effortLevel`, then `CLAUDE_CODE_EFFORT_LEVEL`. The `[1m]` suffix of the model id is stripped for the `modelSettings` lookup (assumed to match how Claude Code keys it; not documented).

| Value | Icon | Note |
|-------|------|------|
| `low` | `◔` | Quick, minimal overhead |
| `medium` | `◑` | Balanced (default on Sonnet 5.5 / Opus 5.5) |
| `high` | `◕` | Thorough |
| `xhigh` | `◉` | Extra-high reasoning budget |
| `max` | `●` | Maximum effort |
| `auto` | `◎` | Legacy payloads only |
| other | `◈` | Level names this script doesn't know yet are shown as-is |

Which levels exist depends on the model (Opus/Sonnet 4.6 have no `xhigh`; Haiku has no effort at all). If a saved level isn't supported, Claude Code falls back to the highest supported one at or below it, and `effort.level` reports what is actually in effect.

> **Note:** `CLAUDE_CODE_EFFORT_LEVEL` overrides `/effort` inside Claude Code itself, so avoid it in the `settings.json` `env` block. The statusline simply mirrors what Claude Code reports.

## Advisor

`advisor:<model>` comes from the transcript's most recent `/advisor` output (session-only changes), falling back to `advisorModel` in settings. The transcript scan is incremental and cached per session (`/tmp/claude-statusline/tx-advisor-<session>`): only bytes appended since the last render are scanned, so very large transcripts (100MB+) cost nothing extra.

## Output Style & Caveman

Rendered as the `output:` group on L3 (3-line mode): `output: ⚙️  default ~ ◕  caveman`. Reads from `output_style.name` in statusline JSON, falling back to `outputStyle` in `settings.local.json`.

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
