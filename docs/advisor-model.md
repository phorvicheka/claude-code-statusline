# Advisor Model in the Statusline

## What Is `advisorModel`

Claude Code supports an `advisorModel` setting in `settings.json` that configures which model is used when the `advisor()` tool is called (the in-session "stronger reviewer"). Example:

```json
{ "advisorModel": "opus" }
```

This is not an on/off toggle — it is a model selector. If absent, Claude Code falls back to its default reviewer model.

## Statusline JSON Support

The Claude Code statusline JSON does **not** currently expose an `advisor_model` field. There is no `advisor.*` key in the payload, so we cannot read it live from the JSON stream.

## What We Can Do

The same fallback strategy used for `effortLevel` and `alwaysThinkingEnabled` applies here: read `advisorModel` from the settings files directly.

Priority order (mirrors Claude Code's own resolution):

1. `{CWD}/.claude/settings.local.json`
2. `~/.claude/settings.local.json`
3. `{CWD}/.claude/settings.json`
4. `~/.claude/settings.json`

Example jq: `jq -r '.advisorModel // empty' settings.json`

## Implementation Sketch

A new `render_advisor` renderer could display:

```
advisor: ◆ opus      (amber — Opus model)
advisor: ◆ sonnet    (blue  — Sonnet model)
advisor: ◆ haiku     (cyan  — Haiku model)
```

The model color would reuse the same palette as `render_model`. If `advisorModel` is absent from all settings files, the element is hidden (same pattern as `render_agent`).

Toggle: `SHOW_ADVISOR=true` (new feature flag).

## Session vs. Persisted

`/advisor [opus|sonnet|off]` is a session-only command (like `/effort max`). The statusline detects it by scanning the transcript JSONL backward for the most recent `/advisor` command output:

```
<local-command-stdout>Advisor set to Opus 4.7
```

If no session command is found, it falls back to the `advisorModel` key in settings files. `/advisor off` (or absent setting) hides the element.

## Current Status

**Implemented.** `render_advisor` reads model in this order:

1. Transcript JSONL — most recent `/advisor` command output (session-only)
2. `advisorModel` in settings JSON files (persisted default)

Toggle: `SHOW_ADVISOR=true` (default on).

## References

- `render_thinking_effort` in `statusline.sh` — settings-fallback + transcript pattern
- `render_agent` in `statusline.sh` — hide-when-empty pattern
