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

The log appends each payload separated by `---`. Useful for diagnosing missing fields, unexpected formats, or path issues.

## Slow renders / TUI stacking

If the statusline + input box stack in scrollback during long runs, the script is taking longer than Claude Code's redraw interval (~300ms). See [performance.md](performance.md) for benchmarks, profiling commands, and tuning knobs.

Quick reset: `rm -rf /tmp/claude-statusline` clears all caches (git, settings, width).
