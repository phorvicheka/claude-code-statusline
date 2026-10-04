# Debugging

Set `STATUSLINE_DEBUG=1` to log the raw JSON that Claude Code sends to `~/.claude/statusline-debug.log`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "STATUSLINE_DEBUG=1 bash ~/.claude/statusline.sh"
  }
}
```

Or enable it for a single session: `STATUSLINE_DEBUG=1 claude`

The log appends each payload separated by `---`, followed by a line such as `TERM_WIDTH=225 (src=COLUMNS, COLUMNS=225) TIER=full ...` showing which width source won (`env` = `TERM_WIDTH`, `COLUMNS`, or `probe`). Useful for diagnosing missing fields, unexpected formats, or path issues.

## Reproducing a payload offline

Pipe a captured payload (one JSON object from the log) into the script. A sandboxed cache dir keeps it from touching your real caches:

```bash
STATUSLINE_CACHE_DIR=$(mktemp -d) TERM_WIDTH=160 bash statusline.sh < payload.json
```

## Tests

`bash tests/run.sh` runs ~60 fixture cases (add `-v` to print each render). Add a case whenever the payload shape or a renderer changes.

## Slow renders / TUI stacking

If the statusline + input box stack in scrollback during long runs, the script is taking longer than Claude Code's redraw interval (~300ms). See [performance.md](performance.md) for benchmarks, profiling commands, and tuning knobs.

Quick reset: `rm -rf /tmp/claude-statusline` clears all caches (git, settings, width).
