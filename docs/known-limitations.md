# Known Limitations

## Clickable Links

Claude Code has a [known bug](https://github.com/anthropics/claude-code/issues/26356) where the Ink renderer strips OSC 8 hyperlink escape sequences. Links work in IDE terminals (VS Code, Cursor) since v2.1.42, but are stripped in standalone terminal mode.

The escape sequences in this statusline are correct per spec. Once Anthropic fixes the Ink renderer, clickable links will work automatically without changes to this script.

**Supported terminals**: iTerm2, Kitty, WezTerm, Windows Terminal, VS Code terminal
**Not supported**: WSL default console, plain xterm, SSH sessions, Git Bash (mintty)
**Auto-detection**: Links are automatically disabled on unsupported terminals.
**Force enable**: `FORCE_HYPERLINK=1` in your settings.json command -- but note that Claude Code's Ink renderer will still strip the sequences in standalone terminal mode. This only helps if you're using a terminal that supports OSC 8 but isn't auto-detected.
**Click**: Cmd+click (macOS) or Ctrl+click (Linux/Windows)

> **Git Bash / mintty note**: `FORCE_HYPERLINK=1 claude` does not help here. Mintty does not support OSC 8 hyperlinks, and Claude Code's Ink renderer strips them in standalone mode regardless. Use VS Code terminal or Windows Terminal for clickable links.

References: [Issue #26356](https://github.com/anthropics/claude-code/issues/26356), [Issue #21586](https://github.com/anthropics/claude-code/issues/21586), [OSC 8 spec](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda)

## Rate Limit Data Freshness

Rate limit values (5h/7d) update only after each Claude assistant response, not in real-time. They may appear stale when idle. This is a Claude Code platform limitation, not a bug in this statusline.

See [rate-limit-staleness.md](rate-limit-staleness.md) for details.

## Auto-Compact Limit (`⟲`)

Claude Code does not send the auto-compact limit in the statusline JSON, and its `used_percentage` is always measured against the full model window. The statusline therefore resolves the limit itself:

1. Env `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (`400000`, `400k`, `1M`).
2. The highest-priority settings file (`$CWD/.claude/settings.local.json`, `~/.claude/settings.local.json`, `$CWD/.claude/settings.json`, `~/.claude/settings.json`) that sets `modelSettings.<model>.autoCompactWindow` or top-level `autoCompactWindow`. Per-model wins inside that file, and `"auto"` means the default display.
3. Clamped to 100k–1M, then lowered by `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`.

The rescale is off when `autoCompactEnabled` is `false`, when `DISABLE_AUTO_COMPACT` or `DISABLE_COMPACT` is set, or when `current_usage` is missing.

Not covered:

- Managed settings and the `--autocompact` launch flag are not read.
- Settings are cached for 120 s, so a `/autocompact` change can take up to two minutes to show.
- `⟲` (U+27F2) may be missing from some Windows console fonts.
