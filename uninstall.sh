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

# -y: no prompts (restore the latest backup if one exists); needed when there is no TTY
AUTO_YES=false
while getopts "y" opt; do
    case "$opt" in
        y) AUTO_YES=true ;;
        *) echo "Usage: uninstall.sh [-y]" >&2; exit 1 ;;
    esac
done

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

info() { printf "${CYAN}[INFO]${RESET}  %s\n" "$1"; }
ok()   { printf "${GREEN}[OK]${RESET}    %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${RESET}  %s\n" "$1"; }

# Our own script carries this header; a backup of it is an older copy of us, not the user's original.
is_ours() { head -n 5 -- "$1" 2>/dev/null | grep -q 'Claude Code Status Line v2'; }

# Newest backup that is NOT ours (glob order = timestamp order; the suffix is epoch seconds)
latest_backup=""
own_backups=()
for f in "${TARGET}".bak.*; do
    [[ -f "$f" ]] || continue
    if is_ours "$f"; then own_backups+=("$f"); else latest_backup="$f"; fi
done

if [[ -n "$latest_backup" ]]; then
    info "Found backup of your previous statusline: ${latest_backup}"
    if [[ "$AUTO_YES" == true ]]; then
        restore="y"
    else
        read -rp "Restore this backup? [Y/n]: " restore
    fi
    if [[ ! "$restore" =~ ^[Nn] ]]; then
        cp "$latest_backup" "$TARGET"
        ok "Restored ${latest_backup} -> ${TARGET}"
    else
        rm -f "$TARGET"
        ok "Removed statusline.sh (no restore)"
    fi
else
    rm -f "$TARGET"
    ok "Removed statusline.sh (no backup of a previous statusline found)"
fi

if (( ${#own_backups[@]} > 0 )); then
    rm -f -- "${own_backups[@]}"
    ok "Removed ${#own_backups[@]} backup(s) of this statusline's older versions"
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
[[ -f "${CLAUDE_DIR}/statusline.conf" ]] && echo "Note: your section settings in ${CLAUDE_DIR}/statusline.conf were kept."
echo "Remove it manually if needed: jq 'del(.statusLine)' ~/.claude/settings.json"
