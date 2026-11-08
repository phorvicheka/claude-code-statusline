---
name: install
description: Install or update the adaptive statusline into ~/.claude/statusline.sh and point settings.json statusLine at it. Use when the user asks to install, set up, update or switch line mode of the adaptive statusline.
disable-model-invocation: true
---

# Install the adaptive statusline

Plugins cannot set `statusLine` themselves, so this skill runs the bundled installer. It copies the script to the
stable path `~/.claude/statusline.sh` (the plugin's own directory changes on every plugin update).

Follow these steps in order. Do not skip the checks.

1. Check dependencies: `command -v jq git`. If `jq` or `git` is missing, stop and tell the user how to install it
   (`sudo apt install jq git` or `brew install jq git`).
2. Show the current setting: `jq '.statusLine // "none"' ~/.claude/settings.json 2>/dev/null || echo none`.
3. If a `statusLine` exists and its `command` does not contain `statusline.sh`, it belongs to another tool. Ask the
   user whether to replace it. If they decline, stop. The installer replaces it without asking.
4. Ask the user which mode they want: 1-line (compact), 2-line, or 3-line (full, the default).
   Skip the question if they already said, or if this is an update and they want to keep the current mode.
5. Run the installer, with N being the chosen mode:
   `bash "${CLAUDE_PLUGIN_ROOT}/install.sh" -y -l N`
6. Report the installer's `[OK]`/`[WARN]` lines. Tell the user the statusline appears on the next render, and that
   after `/plugin update` they must run this skill again, because the installed copy does not update itself.
