---
name: uninstall
description: Remove the adaptive statusline from ~/.claude/statusline.sh and, if the user agrees, its statusLine entry in settings.json. Use when the user asks to uninstall or remove the adaptive statusline.
disable-model-invocation: true
---

# Uninstall the adaptive statusline

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/uninstall.sh" -y`. It restores the newest backup of the user's previous
   (non-adaptive) statusline if one exists, otherwise deletes `~/.claude/statusline.sh`. It also drops backups of
   this statusline's own older versions and removes its cache directory.
2. Show `jq '.statusLine' ~/.claude/settings.json`. If its `command` contains `statusline.sh` and the uninstaller
   printed "Removed statusline.sh", ask the user whether to remove the entry. On yes, run
   `tmp=$(mktemp) && jq 'del(.statusLine)' ~/.claude/settings.json > "$tmp" && [ -s "$tmp" ] && cat "$tmp" > ~/.claude/settings.json; rm -f "$tmp"`.
   Never remove a `statusLine` whose command points at a different tool, or one whose script was just restored.
3. Remind the user that `/plugin uninstall adaptive-statusline@phorvicheka` removes the plugin itself.
