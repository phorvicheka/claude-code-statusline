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
