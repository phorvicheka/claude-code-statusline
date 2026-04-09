#!/usr/bin/env bash
# install.sh — Claude Code Statusline v2 Installer
# Backs up existing config, installs statusline.sh, configures settings.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
TARGET="${CLAUDE_DIR}/statusline.sh"
SETTINGS="${CLAUDE_DIR}/settings.json"
CACHE_DIR="/tmp/claude-statusline"

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
info "Checking dependencies..."

missing=()
command -v bash >/dev/null 2>&1 || missing+=("bash")
command -v jq   >/dev/null 2>&1 || missing+=("jq")
command -v git  >/dev/null 2>&1 || missing+=("git")

if (( ${#missing[@]} > 0 )); then
    error "Missing required tools: ${missing[*]}"
    echo "  Install them before continuing."
    exit 1
fi

# Check bash version >= 4
bash_ver="${BASH_VERSINFO[0]}"
if (( bash_ver < 4 )); then
    warn "Bash version ${BASH_VERSION} detected. Version 4+ recommended."
fi

ok "Dependencies satisfied (bash ${BASH_VERSION}, jq $(jq --version 2>&1), git)"

# Optional: gh CLI for PR# display
if command -v gh >/dev/null 2>&1; then
    ok "Optional: gh CLI found (PR# display enabled)"
else
    warn "Optional: gh CLI not found (PR# display will be hidden)"
    echo "  Install: https://cli.github.com/ then run 'gh auth login'"
fi

# ------------------------------------------------------------------
# 2. Choose line count
# ------------------------------------------------------------------
echo ""
info "Choose your statusline mode:"
echo "  1) 1-line  — compact: model, tokens, git, folder, thinking, cost"
echo "  2) 2-line  — default: adds session IDs, cost group, rate limits"
echo "  3) 3-line  — full: adds worktree details (name, path, branch)"
echo ""
read -rp "Enter 1, 2, or 3 [default: 2]: " line_choice
line_choice="${line_choice:-2}"

case "$line_choice" in
    1|2|3) ;;
    *) warn "Invalid choice '$line_choice', using default (2)"; line_choice=2 ;;
esac

ok "Selected ${line_choice}-line mode"

# ------------------------------------------------------------------
# 3. Backup existing statusline
# ------------------------------------------------------------------
if [[ -f "$TARGET" ]]; then
    backup="${TARGET}.bak.$(date +%s)"
    cp "$TARGET" "$backup"
    ok "Backed up existing statusline to ${backup}"
fi

# ------------------------------------------------------------------
# 4. Install new statusline
# ------------------------------------------------------------------
cp "${SCRIPT_DIR}/statusline.sh" "$TARGET"
chmod +x "$TARGET"

# Set chosen line count in the script (cross-platform sed -i)
if sed --version >/dev/null 2>&1; then
    # GNU sed (Linux/WSL)
    sed -i "s/^STATUSLINE_LINES=\"\${STATUSLINE_LINES:-2}\"/STATUSLINE_LINES=\"\${STATUSLINE_LINES:-${line_choice}}\"/" "$TARGET"
else
    # BSD sed (macOS)
    sed -i '' "s/^STATUSLINE_LINES=\"\${STATUSLINE_LINES:-2}\"/STATUSLINE_LINES=\"\${STATUSLINE_LINES:-${line_choice}}\"/" "$TARGET"
fi

ok "Installed statusline.sh to ${TARGET}"

# ------------------------------------------------------------------
# 5. Configure settings.json
# ------------------------------------------------------------------
mkdir -p "$CLAUDE_DIR"

if [[ -f "$SETTINGS" ]]; then
    # Check if statusLine is already configured
    if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        current_cmd=$(jq -r '.statusLine.command // ""' "$SETTINGS")
        if [[ "$current_cmd" == *"statusline.sh"* ]]; then
            ok "settings.json already configured (statusLine command points to statusline.sh)"
        else
            warn "settings.json has a different statusLine command: $current_cmd"
            read -rp "Overwrite with new config? [y/N]: " overwrite
            if [[ "$overwrite" =~ ^[Yy] ]]; then
                tmp=$(mktemp)
                jq '.statusLine = {"type": "command", "command": "bash '"$TARGET"'"}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
                ok "Updated statusLine in settings.json"
            else
                warn "Skipped settings.json update"
            fi
        fi
    else
        tmp=$(mktemp)
        jq '. + {"statusLine": {"type": "command", "command": "bash '"$TARGET"'"}}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
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
# 6. Create cache directory
# ------------------------------------------------------------------
mkdir -p "$CACHE_DIR"
ok "Cache directory ready: ${CACHE_DIR}"

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
printf "${GREEN}Installation complete!${RESET}\n"
echo ""
echo "  Mode:     ${line_choice}-line"
echo "  Script:   ${TARGET}"
echo "  Settings: ${SETTINGS}"
echo "  Cache:    ${CACHE_DIR}"
echo ""
echo "Start a new Claude Code session to see your statusline."
echo "To change modes at runtime: STATUSLINE_LINES=3 claude"
echo ""
echo "To customize, edit the config flags at the top of:"
echo "  ${TARGET}"
