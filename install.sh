#!/usr/bin/env bash
# install.sh — Claude Code Statusline v2 Installer
# Backs up existing config, installs statusline.sh, configures settings.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
TARGET="${CLAUDE_DIR}/statusline.sh"
SETTINGS="${CLAUDE_DIR}/settings.json"
CACHE_DIR="/tmp/claude-statusline"
# Re-run the statusline every N seconds while Claude Code is idle (0 = don't set).
# Keeps reset countdowns, prompt-cache TTL and git state current; it does NOT make
# rate-limit percentages fresher (see docs/rate-limit-staleness.md).
REFRESH_INTERVAL="${STATUSLINE_REFRESH_INTERVAL:-60}"

# Flags
AUTO_YES=false
while getopts "y" opt; do
    case "$opt" in
        y) AUTO_YES=true ;;
        *) echo "Usage: install.sh [-y]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Detect install vs update
if [[ -f "$TARGET" ]]; then
    ACTION="Updating"
else
    ACTION="Installing"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$1"; }
ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$1"; }
error() { printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2; }

# ------------------------------------------------------------------
# 1. Check dependencies
# ------------------------------------------------------------------
info "${ACTION} Claude Code Statusline v2..."
info "Checking dependencies..."

missing=()
command -v bash >/dev/null 2>&1 || missing+=("bash")
command -v jq   >/dev/null 2>&1 || missing+=("jq")
command -v git  >/dev/null 2>&1 || missing+=("git")

if (( ${#missing[@]} > 0 )); then
    error "Missing required tools: ${missing[*]}"
    echo "  Ubuntu/Debian/WSL: sudo apt install ${missing[*]}"
    echo "  macOS:             brew install ${missing[*]}"
    exit 1
fi

# Check bash version >= 4
bash_ver="${BASH_VERSINFO[0]}"
if (( bash_ver < 4 )); then
    warn "Bash version ${BASH_VERSION} detected. Version 4+ recommended."
fi

ok "Dependencies satisfied (bash ${BASH_VERSION}, jq $(jq --version 2>&1), git)"

# PR / merge-request badge comes from Claude Code's own JSON (pr.*): no gh CLI needed.

# ------------------------------------------------------------------
# 2. Choose line count
# ------------------------------------------------------------------
if [[ "$AUTO_YES" == true ]]; then
    line_choice=3
    ok "Auto mode: using default 3-line mode"
else
    echo ""
    info "Choose your statusline mode:"
    echo "  1) 1-line  — compact: model, tokens, git, folder, thinking, cost"
    echo "  2) 2-line  — adds session IDs, cost group, rate limits"
    echo "  3) 3-line  — full (default): adds worktree details (name, path, branch)"
    echo ""
    read -rp "Enter 1, 2, or 3 [default: 3]: " line_choice
    line_choice="${line_choice:-3}"

    case "$line_choice" in
        1|2|3) ;;
        *) warn "Invalid choice '$line_choice', using default (3)"; line_choice=3 ;;
    esac
fi

ok "Selected ${line_choice}-line mode"

# ------------------------------------------------------------------
# 3. Ensure target directory exists
# ------------------------------------------------------------------
mkdir -p "$CLAUDE_DIR"

# ------------------------------------------------------------------
# 4. Backup existing statusline
# ------------------------------------------------------------------
if [[ -f "$TARGET" ]]; then
    backup="${TARGET}.bak.$(date +%s)"
    cp "$TARGET" "$backup"
    ok "Backed up existing statusline to ${backup}"
fi

# ------------------------------------------------------------------
# 5. Install new statusline
# ------------------------------------------------------------------
cp "${SCRIPT_DIR}/statusline.sh" "$TARGET"
chmod +x "$TARGET"

# Set chosen line count in the script (cross-platform sed -i)
if sed --version >/dev/null 2>&1; then
    # GNU sed (Linux/WSL)
    sed -i "s/^STATUSLINE_LINES=\"\${STATUSLINE_LINES:-[0-9]}\"/STATUSLINE_LINES=\"\${STATUSLINE_LINES:-${line_choice}}\"/" "$TARGET"
else
    # BSD sed (macOS)
    sed -i '' "s/^STATUSLINE_LINES=\"\${STATUSLINE_LINES:-[0-9]}\"/STATUSLINE_LINES=\"\${STATUSLINE_LINES:-${line_choice}}\"/" "$TARGET"
fi

ok "Installed statusline.sh to ${TARGET}"

# ------------------------------------------------------------------
# 6. Configure settings.json
# ------------------------------------------------------------------
if [[ -f "$SETTINGS" ]]; then
    # Check if statusLine is already configured
    if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        current_cmd=$(jq -r '.statusLine.command // ""' "$SETTINGS")
        if [[ "$current_cmd" == *"statusline.sh"* ]]; then
            ok "settings.json already configured (statusLine command points to statusline.sh)"
        else
            warn "settings.json has a different statusLine command: $current_cmd"
            if [[ "$AUTO_YES" == true ]]; then
                overwrite="y"
            else
                read -rp "Overwrite with new config? [y/N]: " overwrite
            fi
            if [[ "$overwrite" =~ ^[Yy] ]]; then
                tmp=$(mktemp)
                jq '.statusLine = {"type": "command", "command": "bash '"$TARGET"'"}' "$SETTINGS" > "$tmp" && [[ -s "$tmp" ]] && cat "$tmp" > "$SETTINGS"; rm -f "$tmp"
                ok "Updated statusLine in settings.json"
            else
                warn "Skipped settings.json update"
            fi
        fi
    else
        tmp=$(mktemp)
        jq '. + {"statusLine": {"type": "command", "command": "bash '"$TARGET"'"}}' "$SETTINGS" > "$tmp" && [[ -s "$tmp" ]] && cat "$tmp" > "$SETTINGS"; rm -f "$tmp"
        ok "Added statusLine config to settings.json"
    fi
else
    cat > "$SETTINGS" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "bash ${TARGET}"
  }
}
EOF
    ok "Created settings.json with statusLine config"
fi

# ------------------------------------------------------------------
# 6b. refreshInterval (only when settings.json points at our script)
# ------------------------------------------------------------------
if [[ "$REFRESH_INTERVAL" =~ ^[0-9]+$ ]] && (( REFRESH_INTERVAL > 0 )) && [[ -f "$SETTINGS" ]] \
   && [[ "$(jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null)" == *"statusline.sh"* ]]; then
    if jq -e '.statusLine | has("refreshInterval")' "$SETTINGS" >/dev/null 2>&1; then
        ok "Keeping existing statusLine.refreshInterval ($(jq -r '.statusLine.refreshInterval' "$SETTINGS")s)"
    else
        tmp=$(mktemp)
        # cat > (not mv) keeps the file's permissions and any symlink to a profile settings file
        if jq --argjson n "$REFRESH_INTERVAL" '.statusLine.refreshInterval = $n' "$SETTINGS" > "$tmp" \
           && [[ -s "$tmp" ]] && cat "$tmp" > "$SETTINGS"; then
            ok "Set statusLine.refreshInterval = ${REFRESH_INTERVAL}s (STATUSLINE_REFRESH_INTERVAL=0 to skip)"
        else
            warn "Could not set refreshInterval in settings.json (left unchanged)"
        fi
        rm -f "$tmp"
    fi
fi

# ------------------------------------------------------------------
# 7. Create cache directory (and drop cache files from older script versions)
# ------------------------------------------------------------------
mkdir -p "$CACHE_DIR"
rm -f "$CACHE_DIR"/git-* "$CACHE_DIR"/settings-* 2>/dev/null || true
ok "Cache directory ready: ${CACHE_DIR}"

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
printf "${GREEN}${ACTION} complete!${RESET}\n"
echo ""
echo "  Mode:     ${line_choice}-line"
echo "  Script:   ${TARGET}"
echo "  Settings: ${SETTINGS}"
echo "  Cache:    ${CACHE_DIR}"
_ri=$(jq -r '.statusLine.refreshInterval // empty' "$SETTINGS" 2>/dev/null || true)
[[ -n "$_ri" ]] && echo "  Refresh:  every ${_ri}s while idle (statusLine.refreshInterval)"
echo ""
echo "Start a new Claude Code session to see your statusline."
echo "To change modes at runtime: STATUSLINE_LINES=3 claude"
echo ""
echo "To customize, edit the config flags at the top of:"
echo "  ${TARGET}"
