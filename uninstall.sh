#!/usr/bin/env bash
# uninstall.sh — Remove Claude Code Statusline v2 and restore backup.

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
TARGET="${CLAUDE_DIR}/statusline.sh"
CACHE_DIR="/tmp/claude-statusline"

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
if [[ -d "$CACHE_DIR" ]]; then
    rm -rf "$CACHE_DIR"
    ok "Removed cache directory: ${CACHE_DIR}"
fi

echo ""
printf "${GREEN}Uninstall complete.${RESET}\n"
echo "Note: statusLine config in settings.json was left intact."
echo "Remove it manually if needed: jq 'del(.statusLine)' ~/.claude/settings.json"
