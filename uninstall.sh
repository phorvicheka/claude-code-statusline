#!/usr/bin/env bash
# uninstall.sh — Remove Claude Code Statusline v2 and restore backup.

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
TARGET="${CLAUDE_DIR}/statusline.sh"
if [[ -n "${XDG_RUNTIME_DIR:-}" && ! -L "$XDG_RUNTIME_DIR" && -d "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]]; then
    CACHE_DIR="${XDG_RUNTIME_DIR}/claude-statusline"
else
    CACHE_DIR="/tmp/claude-statusline-${UID}"
fi
LEGACY_CACHE_DIR="/tmp/claude-statusline"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

info() { printf "${CYAN}[INFO]${RESET}  %s\n" "$1"; }
ok()   { printf "${GREEN}[OK]${RESET}    %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${RESET}  %s\n" "$1"; }

# Find most recent backup
latest_backup=""
for f in "${TARGET}".bak.*; do
    [[ -f "$f" ]] && latest_backup="$f"
done

if [[ -n "$latest_backup" ]]; then
    info "Found backup: ${latest_backup}"
    read -rp "Restore this backup? [Y/n]: " restore
    if [[ ! "$restore" =~ ^[Nn] ]]; then
        cp "$latest_backup" "$TARGET"
        ok "Restored ${latest_backup} -> ${TARGET}"
    else
        rm -f "$TARGET"
        ok "Removed statusline.sh (no restore)"
    fi
else
    rm -f "$TARGET"
    ok "Removed statusline.sh (no backup found)"
fi

# Clean cache
# Only remove directories that are ours; a symlink or someone else's directory is left alone.
for d in "$CACHE_DIR" "$LEGACY_CACHE_DIR"; do
    if [[ -d "$d" && ! -L "$d" && -O "$d" ]]; then
        rm -rf -- "$d"
        ok "Removed cache directory: ${d}"
    fi
done

echo ""
printf "${GREEN}Uninstall complete.${RESET}\n"
echo "Note: statusLine config in settings.json was left intact."
echo "Remove it manually if needed: jq 'del(.statusLine)' ~/.claude/settings.json"
