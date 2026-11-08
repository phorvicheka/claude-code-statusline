---
name: configure
description: Hide or show sections of the adaptive statusline (cost, rate limits, PR, cache, git, model, ...) or change its line mode. Use when the user asks to hide, remove, show, bring back, or list statusline sections, or to switch between 1, 2 and 3 lines.
---

# Configure the adaptive statusline

Settings are saved to `~/.claude/statusline.conf`, so they survive reinstalls and plugin updates. Never edit
`~/.claude/statusline.sh` itself: updates overwrite it.

1. Check that `~/.claude/statusline.sh` exists. If it does not, tell the user to run `/adaptive-statusline:install`
   first, and stop.
2. Map the user's words to section names. Run `bash ~/.claude/statusline.sh --help` for the list. Common ones:
   `cost` (cost, duration, lines changed), `rate-limits` (5h/7d), `pr`, `cache`, `git`, `model`, `tokens`
   (context bar), `version`, `session-id`, `session-name`, `cwd-path`, `worktree`, `advisor`, `effort`,
   `output-style`. If a word matches no section, show the list and ask.
3. Run the matching command:
   - Hide: `bash ~/.claude/statusline.sh --hide <a,b>`
   - Show again: `bash ~/.claude/statusline.sh --show <a,b>`
   - Line mode: `bash ~/.claude/statusline.sh --lines <1|2|3>`
   - Show all, default line mode: `bash ~/.claude/statusline.sh --reset`
   - Current state: `bash ~/.claude/statusline.sh --list`
4. Report the command's output line. The change appears on the next statusline refresh; no restart is needed.
