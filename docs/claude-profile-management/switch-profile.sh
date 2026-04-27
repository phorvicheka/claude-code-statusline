#!/usr/bin/env bash
# switch-profile.sh — apply a Claude Code plugin profile to a project
#
# Usage:
#   switch-profile.sh <profile> [project-dir]
#   ! switch-profile.sh <profile>           ← inside a Claude Code session
#   cc-switch <profile>                     ← if alias is configured (see README)
#
# Profiles:
#   lean           Research, Q&A, web search — minimal token usage
#   artifacts      STAGE 00-02: branch, explore, design, proposals
#   backend-impl   STAGE 03-05: full backend implementation (all plugins)
#   review         STAGE 06-07: code review, PR creation
#   frontend       STAGE 08 or frontend project sessions
#
# The new profile takes effect after restarting Claude Code.

set -euo pipefail

PROFILE="${1:-}"
PROJECT_DIR="${2:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_usage() {
  cat <<EOF
Usage: switch-profile.sh <profile> [project-dir]

Backend profiles:   lean | artifacts | backend-impl | review
Frontend profiles:  lean | frontend  | review

Stage → profile guide (roadmap-phase-processor):
  STAGE 00-02  →  artifacts      (branch, explore, Figma, design, proposals)
  STAGE 03-05  →  backend-impl   (full implementation stack)
  STAGE 06-07  →  review         (codex, pr-review-toolkit, PR creation)
  STAGE 08     →  frontend       (or 'artifacts' inside the backend project)
  STAGE 09     →  lean           (archive, roadmap update — docs only)

Examples:
  switch-profile.sh artifacts
  switch-profile.sh backend-impl
  switch-profile.sh lean ~/projects/ci-telemedicine-doctor-nextjs-front
EOF
}

if [[ -z "$PROFILE" ]] || [[ "$PROFILE" == "--help" ]] || [[ "$PROFILE" == "-h" ]]; then
  print_usage
  exit 0
fi

# Auto-detect project type from build files
detect_type() {
  local dir="$1"
  if [[ -f "$dir/build.gradle.kts" ]] || [[ -f "$dir/build.gradle" ]]; then
    echo "backend"
  elif [[ -f "$dir/package.json" ]]; then
    echo "frontend"
  else
    echo "unknown"
  fi
}

PROJECT_TYPE=$(detect_type "$PROJECT_DIR")

# Resolve the profile settings file
resolve_profile_file() {
  local type="$1"
  local profile="$2"
  local file="$SCRIPT_DIR/$type/settings.$profile.json"

  if [[ -f "$file" ]]; then
    echo "$file"
    return 0
  fi

  # Fallback: frontend lean → backend lean
  if [[ "$type" == "frontend" ]] && [[ -f "$SCRIPT_DIR/backend/settings.$profile.json" ]]; then
    echo "$SCRIPT_DIR/backend/settings.$profile.json"
    return 0
  fi

  echo ""
}

if [[ "$PROJECT_TYPE" == "unknown" ]]; then
  echo "⚠️  Could not detect project type in: $PROJECT_DIR"
  echo "   (no build.gradle.kts or package.json found)"
  echo "   Trying backend profiles as fallback..."
  PROJECT_TYPE="backend"
fi

PROFILE_FILE=$(resolve_profile_file "$PROJECT_TYPE" "$PROFILE")

if [[ -z "$PROFILE_FILE" ]]; then
  echo "❌ No profile file found for: $PROJECT_TYPE / $PROFILE"
  echo ""
  print_usage
  exit 1
fi

CLAUDE_DIR="$PROJECT_DIR/.claude"
if [[ ! -d "$CLAUDE_DIR" ]]; then
  echo "❌ No .claude/ directory found in: $PROJECT_DIR"
  echo "   Make sure you are running this from a Claude Code project root."
  exit 1
fi

# Back up current settings before overwriting
if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
  cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak"
fi

cp "$PROFILE_FILE" "$CLAUDE_DIR/settings.json"

echo "✅ Profile '$PROFILE' applied"
echo "   Project : $PROJECT_DIR ($PROJECT_TYPE)"
echo "   Source  : $PROFILE_FILE"
echo "   Backup  : $CLAUDE_DIR/settings.json.bak"
echo ""
echo "⚡ Restart Claude Code for the new profile to take effect."
echo ""

if [[ "$PROFILE" == "backend-impl" ]]; then
  echo "   Resume : use claude skill 'roadmap-phase-processor' with --auto --impl-all to Continue Phase X"
elif [[ "$PROFILE" == "review" ]]; then
  echo "   Resume : use claude skill 'roadmap-phase-processor' with --auto --impl-all to Continue Phase X"
elif [[ "$PROFILE" == "lean" ]]; then
  echo "   Resume : use claude skill 'roadmap-phase-processor' with --auto --impl-all to Continue Phase X"
fi
