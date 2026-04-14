# Known Limitations

## Clickable Links

Claude Code has a [known bug](https://github.com/anthropics/claude-code/issues/26356) where the Ink renderer strips OSC 8 hyperlink escape sequences. Links work in IDE terminals (VS Code, Cursor) since v2.1.42, but are stripped in standalone terminal mode.

The escape sequences in this statusline are correct per spec. Once Anthropic fixes the Ink renderer, clickable links will work automatically without changes to this script.

**Supported terminals**: iTerm2, Kitty, WezTerm, Windows Terminal, VS Code terminal
**Not supported**: WSL default console, plain xterm, SSH sessions
**Auto-detection**: Links are automatically disabled on unsupported terminals.
**Force enable**: `FORCE_HYPERLINK=1 claude`
**Click**: Cmd+click (macOS) or Ctrl+click (Linux/Windows)

References: [Issue #26356](https://github.com/anthropics/claude-code/issues/26356), [Issue #21586](https://github.com/anthropics/claude-code/issues/21586), [OSC 8 spec](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda)

## Rate Limit Data Freshness

Rate limit values (5h/7d) update only after each Claude assistant response, not in real-time. They may appear stale when idle. This is a Claude Code platform limitation, not a bug in this statusline.

See [rate-limit-staleness.md](rate-limit-staleness.md) for details.
