#!/usr/bin/env bash
# ~/.claude/statusline.sh — Claude Code Status Line v2
# Multi-line, adaptive-width status line with configurable elements.
#
# References:
#   https://code.claude.com/docs/en/statusline
#   https://github.com/isaacaudet/claude-code-statusline
#   https://github.com/sirmalloc/ccstatusline

set -f  # disable globbing
shopt -s extglob  # used by _vis_len to strip ANSI sequences without forking

# ===========================================================================
# Configuration
# ===========================================================================

# ── Line count (override via env: STATUSLINE_LINES=3 claude) ──
STATUSLINE_LINES="${STATUSLINE_LINES:-3}"  # 1, 2, or 3

# ── Feature toggles (set false to hide any element) ──
SHOW_MODEL=true
SHOW_TOKENS=true
SHOW_GIT=true
SHOW_FOLDER=true
SHOW_THINKING=true   # thinking + effort combined block
SHOW_EFFORT=true     # part of thinking+effort block
SHOW_OUTPUT_STYLE=true
SHOW_CAVEMAN=true
SHOW_AGENT=true
SHOW_ADVISOR=true
SHOW_VIM_MODE=true
SHOW_VERSION=true
SHOW_SESSION_ID=true
SHOW_SESSION_NAME=true
SHOW_COST_GROUP=true
SHOW_RATE_LIMITS=true
SHOW_WORKTREE=true
SHOW_PR=true
SHOW_FAST=true       # ⚡ badge while fast mode is on
SHOW_CACHE=true      # prompt-cache warm/cold badge (L2, wide+ tiers only)
SHOW_SPEND=true      # gateway spend-limit meter (L2, only when present)
SHOW_CWD_PATH=true   # user@host:~/path on the host row (deduped vs worktree path)
SHOW_CLICKABLE_LINKS=true

# Auto-detect terminals that do NOT support OSC 8 clickable links.
# WSL default console (conhost.exe), plain xterm, and most SSH sessions
# don't support OSC 8. Only enable for known-good terminals.
# Override with FORCE_HYPERLINK=1 to force links on.
if [[ "${FORCE_HYPERLINK:-0}" != "1" ]] && $SHOW_CLICKABLE_LINKS; then
    _osc8_supported=false
    case "${TERM_PROGRAM:-}" in
        iTerm*|WezTerm|vscode) _osc8_supported=true ;;
    esac
    # Windows Terminal sets WT_SESSION
    [[ -n "${WT_SESSION:-}" ]] && _osc8_supported=true
    # Kitty sets KITTY_PID
    [[ -n "${KITTY_PID:-}" ]] && _osc8_supported=true
    $_osc8_supported || SHOW_CLICKABLE_LINKS=false
fi

# ── Sizing ──
GIT_CACHE_TTL=30        # cache git branch/dirty/ahead-behind (PR data now comes free from
                        # Claude Code's JSON, so the old 300s `gh pr view` ceiling is gone).
                        # Keeps the branch from lagging a `git checkout` by minutes.
GIT_CACHE_TTL_SLOW=300  # same cache, for repos on WSL2 /mnt/* (9p) hosts where git is slow.
SETTINGS_CACHE_TTL=120  # cache parsed settings.json values (4 files, 6 keys).
                        # See docs/performance.md. Bumped 30→120.
WIDTH_CACHE_TTL=300     # cache TERM_WIDTH per parent pid (avoid /proc walk every run).
                        # Bumped 30→300 (terminal resize rare).
MAX_BRANCH_LEN=50       # truncate branch names beyond this (full tier)
TOKEN_BAR_WIDTH=10      # context bar width in characters
RATE_BAR_WIDTH=10       # rate limit bar width in characters

# ── Color thresholds for progress bars ──
THRESHOLD_GREEN=50      # below this = green
THRESHOLD_YELLOW=75     # below this = yellow, above = red

# ===========================================================================
# ANSI Colors
# ===========================================================================
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_WHITE='\033[0;37m'
C_AMBER='\033[38;5;208m'
C_DIM='\033[2m'
C_RESET='\033[0m'

SEP=" ${C_DIM}|${C_RESET} "
TILDE=" ${C_DIM}~${C_RESET} "

# ===========================================================================
# Cache root
# A predictable world-writable /tmp path would let any local user plant cache
# files that get read back into this script, or symlinks that our writes would
# follow. So: $XDG_RUNTIME_DIR/claude-statusline (per-user, 0700) when available,
# else /tmp/claude-statusline-$UID created 0700. Symlinks and directories owned
# by someone else are refused; on any doubt CACHE_ROOT is "" and every cache is
# skipped (slower, still correct). Override for tests: STATUSLINE_CACHE_DIR=/x
# (same ownership / symlink checks, mode not enforced).
# ===========================================================================
_init_cache_root() {
    local base="${STATUSLINE_CACHE_DIR:-}"
    if [[ -z "$base" ]]; then
        if [[ -n "${XDG_RUNTIME_DIR:-}" && ! -L "$XDG_RUNTIME_DIR" && -d "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]]; then
            base="${XDG_RUNTIME_DIR}/claude-statusline"
        else
            base="/tmp/claude-statusline-${UID}"
        fi
    fi
    if [[ ! -e "$base" && ! -L "$base" ]]; then
        ( umask 077; mkdir -p -- "$base" ) 2>/dev/null
    fi
    # Symlink test FIRST: -d and -O both follow links.
    if [[ ! -L "$base" && -d "$base" && -O "$base" ]]; then
        CACHE_ROOT="$base"
    else
        CACHE_ROOT=""
    fi
}
CACHE_ROOT=""
_init_cache_root

# _cache_write <file> <content>: atomic and symlink-safe. Writes a private temp
# file (noclobber) next to the target, then renames over it; rename replaces a
# planted symlink instead of following it.
_cache_write() {
    local f="$1"
    [[ -n "$CACHE_ROOT" && "$f" == "$CACHE_ROOT"/* ]] || return 0
    [[ -d "$f" ]] && return 0
    local tmp="${f}.$$"
    rm -f -- "$tmp" 2>/dev/null
    if ( set -C; umask 077; printf '%s' "$2" > "$tmp" ) 2>/dev/null; then
        [[ -L "$f" ]] && rm -f -- "$f" 2>/dev/null
        mv -f -- "$tmp" "$f" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
    else
        rm -f -- "$tmp" 2>/dev/null
    fi
    return 0
}

# Age in seconds of a cache file (999999 when missing / a symlink / unreadable).
_cache_age() {
    local f="$1" mtime now
    [[ -f "$f" && ! -L "$f" ]] || { printf '999999'; return; }
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    printf -v now '%(%s)T' -1 2>/dev/null || now=$(date +%s)
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    printf '%s' $(( now - mtime ))
}

# ===========================================================================
# Read JSON from stdin
# ===========================================================================
INPUT=$(cat)
if [[ -z "$INPUT" ]]; then
    printf "Claude"
    exit 0
fi

# ===========================================================================
# Debug hook: set STATUSLINE_DEBUG=1 to log raw JSON to a file
# ===========================================================================
if [[ "${STATUSLINE_DEBUG:-0}" == "1" ]]; then
    printf '%s\n---\n' "$INPUT" >> "${HOME}/.claude/statusline-debug.log"
fi

# ===========================================================================
# Parse all fields in a single jq call
# ===========================================================================
eval "$(printf '%s' "$INPUT" | jq -r '
  # Every field is reduced to a shell-quoted scalar before it reaches eval:
  #  - sc : objects / arrays / null become "" (jq @sh aborts on objects, which
  #         used to drop every field emitted after the offending one)
  #  - q  : sc + @sh quoting, so a hostile value can never run as shell code
  #  - num: only real JSON numbers pass; anything else becomes the default
  #  - g  : safe path access (a field that changed type cannot abort the parse)
  def sc: if . == null or type == "object" or type == "array" then "" else tostring end;
  def q: sc | @sh;
  def num(d): if type == "number" then tostring else d end;
  def g(f): try f catch null;
  def bool(f): (g(f) == true) | tostring;
  def firststr(xs): [xs | select(type == "string" and length > 0)] | (.[0] // "");

  # Claude Code sends effort and thinking as OBJECTS ({"level":..}, {"enabled":..});
  # older builds / docs variants used scalars. Accept both. `//` is avoided on
  # purpose: it treats `false` as missing, which would turn "thinking off" into "unknown".
  (g(.thinking) | if type == "object" then .enabled else . end) as $think
  | ([$think, g(.is_thinking), g(.alwaysThinkingEnabled)] | map(select(type == "boolean")) | .[0]) as $thinking_on
  | (g(.effort) | if type == "object" then .level else . end) as $effort_obj
  | "MODEL_DISPLAY=" + (firststr(g(.model.display_name)) | if . == "" then "Unknown" else . end | @sh),
  "MODEL_ID=" + (g(.model.id) | q),
  "CWD=" + (g(.cwd) | q),
  "WORKSPACE_DIR=" + (g(.workspace.current_dir) | q),
  "PROJECT_DIR=" + (g(.workspace.project_dir) | q),
  "WS_MODERN=" + ((g(.workspace) | type == "object" and has("added_dirs")) | tostring),
  "GIT_WORKTREE_JSON=" + (g(.workspace.git_worktree) | q),
  "REPO_HOST=" + (g(.workspace.repo.host) | q),
  "REPO_OWNER=" + (g(.workspace.repo.owner) | q),
  "REPO_NAME=" + (g(.workspace.repo.name) | q),
  "SESSION_ID=" + (g(.session_id) | q),
  "SESSION_NAME=" + (g(.session_name) | q),
  "VIM_MODE=" + (g(.vim.mode) | q),
  "AGENT_NAME=" + (g(.agent.name) | q),
  "WORKTREE_NAME=" + (g(.worktree.name) | q),
  "WORKTREE_PATH=" + (g(.worktree.path) | q),
  "WORKTREE_BRANCH=" + (g(.worktree.branch) | q),
  "CC_VERSION=" + (g(.version) | q),
  "CTX_SIZE=" + (g(.context_window.context_window_size) | num("0")),
  "USED_PCT=" + (g(.context_window.used_percentage) | num("0")),
  "INPUT_TOKENS=" + (
    if (g(.context_window.current_usage) | type) == "object" then
      ((g(.context_window.current_usage.input_tokens) | num("0") | tonumber)
       + (g(.context_window.current_usage.cache_creation_input_tokens) | num("0") | tonumber)
       + (g(.context_window.current_usage.cache_read_input_tokens) | num("0") | tonumber))
    else
      (g(.context_window.total_input_tokens) | num("0") | tonumber)
    end | tostring
  ),
  "EXCEEDS_200K=" + ([g(.exceeds_200k_tokens), g(.context_window.exceeds_200k_tokens)] | map(select(type == "boolean")) | (.[0] // false) | tostring),
  "TOTAL_COST=" + (g(.cost.total_cost_usd) | num("0")),
  "TOTAL_DURATION_MS=" + (g(.cost.total_duration_ms) | num("0")),
  "LINES_ADDED=" + (g(.cost.total_lines_added) | num("0")),
  "LINES_REMOVED=" + (g(.cost.total_lines_removed) | num("0")),
  "RATE_5H_PCT=" + (g(.rate_limits.five_hour.used_percentage) | num("-1")),
  "RATE_5H_RESETS=" + (g(.rate_limits.five_hour.resets_at) | q),
  "RATE_7D_PCT=" + (g(.rate_limits.seven_day.used_percentage) | num("-1")),
  "RATE_7D_RESETS=" + (g(.rate_limits.seven_day.resets_at) | q),
  "SPEND_PCT=" + (g(.rate_limits.spend_limit.used_percentage) | num("-1")),
  "SPEND_RESETS=" + (g(.rate_limits.spend_limit.resets_at) | q),
  "SPEND_USED=" + (g(.rate_limits.spend_limit.used_usd) | num("")),
  "SPEND_LIMIT=" + (g(.rate_limits.spend_limit.limit_usd) | num("")),
  "SPEND_PERIOD=" + (g(.rate_limits.spend_limit.period) | q),
  "OUTPUT_STYLE=" + (g(.output_style.name) | q),
  "IS_THINKING=" + (if $thinking_on == null then "unknown" else ($thinking_on | tostring) end | @sh),
  "EFFORT_LEVEL_JSON=" + (firststr($effort_obj, g(.effort_level), g(.effortLevel)) | @sh),
  # Modern payloads always carry thinking/fast_mode; an absent `effort` then means
  # "model has no effort parameter" (e.g. Haiku), not "unknown".
  "MODERN_SCHEMA=" + ((type == "object" and (has("thinking") or has("fast_mode"))) | tostring),
  "FAST_MODE=" + bool(.fast_mode),
  "PR_NUMBER=" + (g(.pr.number) | q),
  "PR_URL=" + (g(.pr.url) | q),
  "PR_STATE=" + (g(.pr.review_state) | q),
  "PR_KIND=" + (g(.pr.kind) | q),
  "PC_PRESENT=" + ((g(.prompt_cache) | type == "object") | tostring),
  "PC_OBSERVED=" + bool(.prompt_cache.caching_observed),
  "PC_WARM=" + bool(.prompt_cache.warm),
  "PC_EXPIRES=" + (g(.prompt_cache.expires_at) | num("")),
  "PC_HIT=" + (g(.prompt_cache.hit_ratio) | num("")),
  "TRANSCRIPT_PATH=" + (g(.transcript_path) | q)
' 2>/dev/null)" || true

# Defaults for unparseable input
: "${MODEL_DISPLAY:=Unknown}" "${CWD:=}" "${CTX_SIZE:=0}" "${USED_PCT:=0}"
: "${INPUT_TOKENS:=0}" "${TOTAL_COST:=0}" "${TOTAL_DURATION_MS:=0}"
: "${LINES_ADDED:=0}" "${LINES_REMOVED:=0}"
: "${RATE_5H_PCT:=-1}" "${RATE_5H_RESETS:=}" "${RATE_7D_PCT:=-1}" "${RATE_7D_RESETS:=}"
: "${SPEND_PCT:=-1}" "${SPEND_RESETS:=}" "${SPEND_USED:=}" "${SPEND_LIMIT:=}" "${SPEND_PERIOD:=}"
: "${OUTPUT_STYLE:=}" "${IS_THINKING:=unknown}"
: "${EFFORT_LEVEL_JSON:=}" "${MODERN_SCHEMA:=false}" "${WS_MODERN:=false}" "${TRANSCRIPT_PATH:=}"
: "${FAST_MODE:=false}" "${GIT_WORKTREE_JSON:=}" "${REPO_HOST:=}" "${REPO_OWNER:=}" "${REPO_NAME:=}"
: "${PR_NUMBER:=}" "${PR_URL:=}" "${PR_STATE:=}" "${PR_KIND:=}"
: "${PC_PRESENT:=false}" "${PC_OBSERVED:=false}" "${PC_WARM:=false}" "${PC_EXPIRES:=}" "${PC_HIT:=}"
# Anything that ends up in a bash arithmetic context must be a plain number.
for _v in CTX_SIZE INPUT_TOKENS LINES_ADDED LINES_REMOVED TOTAL_DURATION_MS; do
    [[ "${!_v}" =~ ^[0-9]+$ ]] || printf -v "$_v" '%s' 0
done
for _v in RATE_5H_PCT RATE_7D_PCT SPEND_PCT; do
    [[ "${!_v}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || printf -v "$_v" '%s' -1
done
[[ "$USED_PCT"   =~ ^[0-9]+(\.[0-9]+)?$ ]] || USED_PCT=0
[[ "$TOTAL_COST" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || TOTAL_COST=0
[[ "$PR_NUMBER"  =~ ^[0-9]+$ ]] || PR_NUMBER=""
[[ "$PC_EXPIRES" =~ ^[0-9]+$ ]] || PC_EXPIRES=""
[[ "$PC_HIT"     =~ ^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]] || PC_HIT=""
unset _v

# ===========================================================================
# Normalize Windows backslash paths
# Claude Code may send paths like C:\Users\foo\project on Windows.
# IMPORTANT: use tr, not ${var//\\//} — bash parameter expansion silently
# fails to replace backslashes in MINGW64 piped execution contexts.
# ===========================================================================
_to_fwd() { printf '%s' "$1" | tr '\134' '/'; }
CWD=$(_to_fwd "$CWD")
WORKSPACE_DIR=$(_to_fwd "$WORKSPACE_DIR")
PROJECT_DIR=$(_to_fwd "$PROJECT_DIR")
WORKTREE_PATH=$(_to_fwd "$WORKTREE_PATH")

# ===========================================================================
# Auto-detect git worktree when Claude Code JSON doesn't provide it
# A linked worktree has git-dir != git-common-dir (e.g., .git/worktrees/<name>)
# ===========================================================================
_detect_worktree() {
    local dir="$1"
    [[ -z "$dir" || ! -d "$dir" ]] && return

    local git_dir common_dir
    git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null) || return
    common_dir=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return

    # Normalize to absolute paths for comparison
    git_dir=$(cd "$dir" && cd "$git_dir" && pwd)
    common_dir=$(cd "$dir" && cd "$common_dir" && pwd)

    [[ "$git_dir" == "$common_dir" ]] && return  # not a linked worktree

    # This IS a linked worktree — populate name, path, branch.
    # Path: the worktree ROOT, even when $dir is a subdirectory of it. --show-prefix
    # (dir relative to the root) is subtracted from $dir, so a symlinked $dir keeps
    # its spelling; --show-toplevel is git's resolved spelling (used for porcelain matches).
    local info prefix top root="${dir%/}"
    info=$(git -C "$dir" rev-parse --show-prefix --show-toplevel 2>/dev/null) || info=""
    if [[ "$info" == *$'\n'* ]]; then
        prefix="${info%%$'\n'*}"; prefix="${prefix%/}"
        top="${info#*$'\n'}"
        [[ -n "$prefix" && "$root" == *"/$prefix" ]] && root="${root%"/$prefix"}"
    else
        top="$root"
    fi
    # Name: prefer the real worktree name from workspace.git_worktree.
    [[ -z "$WORKTREE_NAME" ]] && WORKTREE_NAME="${GIT_WORKTREE_JSON:-${root##*/}}"
    WORKTREE_PATH="$root"

    # Find branch: check if any worktree at this path has a branch
    local wt_path="" wt_branch=""
    while IFS= read -r line; do
        case "$line" in
            "worktree "*)  wt_path="${line#worktree }" ;;
            "branch "*)    wt_branch="${line#branch refs/heads/}" ;;
            "")
                if [[ ( "$wt_path" == "$root" || "$wt_path" == "$top" ) && -n "$wt_branch" ]]; then
                    WORKTREE_BRANCH="$wt_branch"
                    return
                fi
                wt_path="" ; wt_branch=""
                ;;
        esac
    done < <(git -C "$dir" worktree list --porcelain 2>/dev/null; echo "")

    # Detached HEAD worktree: find the branch from the main worktree at the same commit
    if [[ -z "$WORKTREE_BRANCH" ]]; then
        local my_head
        my_head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || return
        wt_path="" ; wt_branch=""
        local wt_head=""
        while IFS= read -r line; do
            case "$line" in
                "worktree "*)  wt_path="${line#worktree }" ;;
                "HEAD "*)      wt_head="${line#HEAD }" ;;
                "branch "*)    wt_branch="${line#branch refs/heads/}" ;;
                "")
                    if [[ "$wt_path" != "$root" && "$wt_path" != "$top" && "$wt_head" == "$my_head" && -n "$wt_branch" ]]; then
                        WORKTREE_BRANCH="$wt_branch"
                        return
                    fi
                    wt_path="" ; wt_head="" ; wt_branch=""
                    ;;
            esac
        done < <(git -C "$dir" worktree list --porcelain 2>/dev/null; echo "")
    fi
}

# Modern Claude Code (workspace.added_dirs present) states definitively whether the
# cwd is a linked worktree: workspace.git_worktree is set, or absent. Absent means
# "main working tree", so skip the git forks entirely (they ran on every render).
# Older payloads have no such signal, so fall back to probing git.
if [[ -z "$WORKTREE_NAME" ]]; then
    if [[ "$WS_MODERN" != "true" || -n "$GIT_WORKTREE_JSON" ]]; then
        _detect_worktree "$(_to_fwd "${CWD:-$WORKSPACE_DIR}")"
    fi
    if [[ -z "$WORKTREE_NAME" && -n "$GIT_WORKTREE_JSON" ]]; then
        WORKTREE_NAME="$GIT_WORKTREE_JSON"
        WORKTREE_PATH="$(_to_fwd "${CWD:-$WORKSPACE_DIR}")"
    fi
fi

# ===========================================================================
# Settings preload (single-pass cache)
# Replaces 6 scattered jq calls across render_thinking_effort,
# render_output_style, render_advisor with one merged read per CWD.
# Each renderer consumes the SETTINGS_* globals below.
# Priority order (first non-empty wins):
#   $CWD/.claude/settings.local.json
#   $HOME/.claude/settings.local.json
#   $CWD/.claude/settings.json
#   $HOME/.claude/settings.json
# ===========================================================================
SETTINGS_THINKING=""
SETTINGS_EFFORT_LEVEL=""
SETTINGS_EFFORT_MODEL=""   # modelSettings.<model-id>.effortLevel (beats top-level effortLevel)
SETTINGS_EFFORT_ENV=""
SETTINGS_OUTPUT_STYLE=""
SETTINGS_ADVISOR_MODEL=""

# The cache file is plain KEY=value lines and is read back through a whitelist:
# it is never `source`d / eval'd, and values lose control characters.
_read_settings_cache() {
    local k v
    # `|| [[ -n $k ]]`: the last line has no trailing newline ($(...) strips it).
    while IFS='=' read -r k v || [[ -n "$k" ]]; do
        case "$k" in
            SETTINGS_THINKING|SETTINGS_EFFORT_LEVEL|SETTINGS_EFFORT_MODEL|SETTINGS_EFFORT_ENV|SETTINGS_OUTPUT_STYLE|SETTINGS_ADVISOR_MODEL)
                printf -v "$k" '%s' "${v//[[:cntrl:]]/}" ;;
        esac
    done < "$1" 2>/dev/null
}

_load_settings() {
    # Key by cwd + model: the per-model effort lookup depends on the model id.
    # "settings2-" prefix: older "settings-*" files lack SETTINGS_EFFORT_MODEL.
    local model_key="${MODEL_ID%%\[*}"   # claude-sonnet-5-5[1m] -> claude-sonnet-5-5 (assumed to match CC's key)
    local cache_file=""
    if [[ -n "$CACHE_ROOT" ]]; then
        local cwd_hash
        cwd_hash=$(printf '%s|%s' "${CWD:-_}" "$model_key" | cksum | awk '{print $1}')
        cache_file="${CACHE_ROOT}/settings2-${cwd_hash}"
        if (( $(_cache_age "$cache_file") < SETTINGS_CACHE_TTL )); then
            _read_settings_cache "$cache_file"
            return 0
        fi
    fi

    local thinking="" effort_level="" effort_model="" effort_env="" output_style="" advisor_model=""
    local f parsed k v
    for f in "${CWD}/.claude/settings.local.json" "${HOME}/.claude/settings.local.json" \
              "${CWD}/.claude/settings.json"       "${HOME}/.claude/settings.json"; do
        [[ -f "$f" ]] || continue
        # Single jq pass per file: extract all 6 keys at once
        parsed=$(jq -r --arg m "$model_key" '
            "T=" + (if has("alwaysThinkingEnabled") then (.alwaysThinkingEnabled | tostring) else "" end),
            "E=" + (if has("effortLevel") then .effortLevel else "" end),
            "EM=" + (try ((.modelSettings // {})[$m].effortLevel // "") catch ""),
            "EV=" + (.env.CLAUDE_CODE_EFFORT_LEVEL // ""),
            "O=" + (if has("outputStyle") then .outputStyle else "" end),
            "A=" + (if has("advisorModel") then .advisorModel else "" end)
        ' "$f" 2>/dev/null) || continue
        while IFS='=' read -r k v; do
            v="${v//[[:cntrl:]]/}"
            case "$k" in
                T)  [[ -z "$thinking"      && -n "$v" ]] && thinking="$v" ;;
                E)  [[ -z "$effort_level"  && -n "$v" ]] && effort_level="$v" ;;
                EM) [[ -z "$effort_model"  && -n "$v" ]] && effort_model="$v" ;;
                EV) [[ -z "$effort_env"    && -n "$v" ]] && effort_env="$v" ;;
                O)  [[ -z "$output_style"  && -n "$v" ]] && output_style="$v" ;;
                A)  [[ -z "$advisor_model" && -n "$v" ]] && advisor_model="$v" ;;
            esac
        done <<< "$parsed"
    done
    SETTINGS_THINKING="$thinking"; SETTINGS_EFFORT_LEVEL="$effort_level"
    SETTINGS_EFFORT_MODEL="$effort_model"; SETTINGS_EFFORT_ENV="$effort_env"
    SETTINGS_OUTPUT_STYLE="$output_style"; SETTINGS_ADVISOR_MODEL="$advisor_model"

    [[ -n "$cache_file" ]] && _cache_write "$cache_file" "$(
        printf 'SETTINGS_THINKING=%s\nSETTINGS_EFFORT_LEVEL=%s\nSETTINGS_EFFORT_MODEL=%s\n' "$thinking" "$effort_level" "$effort_model"
        printf 'SETTINGS_EFFORT_ENV=%s\nSETTINGS_OUTPUT_STYLE=%s\nSETTINGS_ADVISOR_MODEL=%s\n' "$effort_env" "$output_style" "$advisor_model"
    )"
    return 0
}
_load_settings

# ===========================================================================
# Terminal width detection
# When run as a statusline command, stdin is a JSON pipe — there is no TTY.
# Tools like tput/stty return bogus defaults (80) in that context.
# Only trust detection when stdout is a real terminal; otherwise default
# to 200 (full tier) and let Claude Code handle display wrapping.
# Override: set TERM_WIDTH in the statusLine command or env.
# ===========================================================================
_width_cache_key() {
    # Key by parent pid (claude binary). Survives across statusline invocations
    # within a single Claude Code session. Stale on terminal resize until TTL.
    local pp
    pp=$(awk '{print $4}' /proc/$$/stat 2>/dev/null) || pp=""
    [[ -z "$pp" || "$pp" == "0" ]] && return 1
    printf '%s' "$pp"
}

_get_cached_width() {
    local key
    key=$(_width_cache_key) || return 1
    [[ -n "$CACHE_ROOT" ]] || return 1
    local cache_file="${CACHE_ROOT}/width-${key}"
    (( $(_cache_age "$cache_file") < WIDTH_CACHE_TTL )) || return 1
    local w=""
    IFS= read -r w < "$cache_file" 2>/dev/null
    # Used in arithmetic later: digits only.
    [[ "$w" =~ ^[0-9]{1,5}$ ]] || return 1
    printf '%s' "$w"
}

_save_cached_width() {
    local width="$1"
    [[ "${width:-0}" -gt 0 ]] 2>/dev/null || return
    local key
    key=$(_width_cache_key) || return
    _cache_write "${CACHE_ROOT}/width-${key}" "$width"
}

# Claude Code sets COLUMNS/LINES to the real terminal size before running the
# script (https://code.claude.com/docs/en/statusline), so COLUMNS is authoritative.
# The cache / tput / /proc-walk chain below only serves builds that don't set it.
_width_src="env"
if [[ "${TERM_WIDTH:-0}" -le 0 ]] 2>/dev/null; then
    _width_src="COLUMNS"
    if [[ "${COLUMNS:-0}" -gt 0 ]] 2>/dev/null; then
        TERM_WIDTH=$COLUMNS
    else
        _width_src="probe"
        # Try cache first to avoid /proc walk on every render
        _cached_w=$(_get_cached_width)
        if [[ "${_cached_w:-0}" -gt 0 ]] 2>/dev/null; then
            TERM_WIDTH=$_cached_w
        elif [[ -t 1 ]]; then
            # stdout is a terminal — detection is trustworthy
            _w=$(tput cols 2>/dev/null) \
                || _w=$(stty size </dev/tty 2>/dev/null | awk '{print $2}') \
                || _w=$(mode con 2>/dev/null | awk '/Columns:/{gsub(/[^0-9]/,"",$2); print $2}') \
                || _w=0
            [[ "${_w:-0}" -gt 0 ]] 2>/dev/null && TERM_WIDTH=$_w || TERM_WIDTH=200
            _save_cached_width "$TERM_WIDTH"
            unset _w
        else
            # Piped by Claude Code — try /dev/tty, then walk process tree for parent pts.
            _w=$(stty size </dev/tty 2>/dev/null | awk '{print $2}') || _w=0
            if [[ "${_w:-0}" -le 0 ]]; then
                # Claude Code doesn't pass a controlling terminal, but a parent process
                # (the claude binary itself) still has the pts device open.
                # Walk up to 5 ancestors looking for a pts fd.
                _pid=$$
                for _i in 1 2 3 4 5; do
                    _ppid=$(awk '{print $4}' /proc/$_pid/stat 2>/dev/null) || break
                    [[ -z "$_ppid" || "$_ppid" == "0" ]] && break
                    _pts=$(readlink /proc/$_ppid/fd/[0-9]* 2>/dev/null \
                           | awk '/\/dev\/pts\//{print; exit}')
                    if [[ -n "$_pts" ]]; then
                        _w=$(stty size < "$_pts" 2>/dev/null | awk '{print $2}')
                        [[ "${_w:-0}" -gt 0 ]] && break
                    fi
                    _pid=$_ppid
                done
                unset _pid _ppid _pts _i
            fi
            [[ "${_w:-0}" -gt 0 ]] 2>/dev/null && TERM_WIDTH=$_w || TERM_WIDTH=200
            _save_cached_width "$TERM_WIDTH"
            unset _w
        fi
        unset _cached_w
    fi
fi

# TERM_WIDTH feeds bash arithmetic: digits only, whatever its source.
[[ "$TERM_WIDTH" =~ ^[0-9]{1,5}$ ]] || TERM_WIDTH=200

# Width tier: full(>=140), wide(100-139), compact(76-99), narrow(<76)
if   (( TERM_WIDTH >= 140 )); then TIER="full"
elif (( TERM_WIDTH >= 100 )); then TIER="wide"
elif (( TERM_WIDTH >=  76 )); then TIER="compact"
else                                TIER="narrow"
fi

# Adjust sizing per tier
case "$TIER" in
    full)    _branch_max=$MAX_BRANCH_LEN; _token_bar=$TOKEN_BAR_WIDTH; _rate_bar=$RATE_BAR_WIDTH ;;
    wide)    _branch_max=50; _token_bar=8; _rate_bar=8 ;;
    compact) _branch_max=30; _token_bar=6; _rate_bar=6 ;;
    narrow)  _branch_max=15; _token_bar=4; _rate_bar=4 ;;
esac

# Dynamic folder cap: show as much as fits in L1 without overflowing TERM_WIDTH.
# Fixed L1 overhead ≈ 70 chars (model + seps + tokens + git-prefix + dirty-indicator),
# +2 while the ⚡ fast-mode badge is shown.
_l1_overhead=70
[[ "$FAST_MODE" == "true" ]] && _l1_overhead=72
_folder_max=$(( TERM_WIDTH - _l1_overhead - _branch_max ))
(( _folder_max < 10 )) && _folder_max=10

if [[ "${STATUSLINE_DEBUG:-0}" == "1" ]]; then
    printf 'TERM_WIDTH=%s (src=%s, COLUMNS=%s) TIER=%s _branch_max=%s _folder_max=%s\n' \
        "$TERM_WIDTH" "$_width_src" "${COLUMNS:-unset}" "$TIER" "$_branch_max" "$_folder_max" \
        >> "${HOME}/.claude/statusline-debug.log"
fi

# In narrow tier, force single line
if [[ "$TIER" == "narrow" ]]; then
    STATUSLINE_LINES=1
fi

# ===========================================================================
# Utility functions
# ===========================================================================

pct_color() {
    local pct="${1%.*}"
    pct="${pct:-0}"
    if   (( pct < THRESHOLD_GREEN  )); then printf '%s' "$C_GREEN"
    elif (( pct < THRESHOLD_YELLOW )); then printf '%s' "$C_YELLOW"
    else                                    printf '%s' "$C_RED"
    fi
}

build_bar() {
    local pct="${1%.*}" width="$2"
    pct="${pct:-0}"
    (( pct < 0 ))   && pct=0
    (( pct > 100 )) && pct=100
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local color
    color=$(pct_color "$pct")
    # Build bar string without per-char loop
    local filled_str="" empty_str=""
    (( filled > 0 )) && printf -v filled_str '%*s' "$filled" '' && filled_str="${filled_str// /█}"
    (( empty  > 0 )) && printf -v empty_str  '%*s' "$empty"  '' && empty_str="${empty_str// /░}"
    printf '%b%s%s%b' "$color" "$filled_str" "$empty_str" "$C_RESET"
}

fmt_tokens() {
    local n="$1"
    if (( n >= 1000000 )); then
        awk "BEGIN {printf \"%.1fm\", $n / 1000000}"
    elif (( n >= 1000 )); then
        printf '%dk' "$(( n / 1000 ))"
    else
        printf '%d' "$n"
    fi
}

fmt_duration() {
    local ms="$1"
    local total_sec=$(( ms / 1000 ))
    local h=$(( total_sec / 3600 ))
    local m=$(( (total_sec % 3600) / 60 ))
    local s=$(( total_sec % 60 ))
    if (( h > 0 )); then
        printf '%dh%dm' "$h" "$m"
    elif (( m > 0 )); then
        printf '%dm%ds' "$m" "$s"
    else
        printf '%ds' "$s"
    fi
}

fmt_reset_time() {
    local resets_at="$1"
    [[ -z "$resets_at" || "$resets_at" == "0" ]] && return

    # Convert to epoch seconds — handle both unix timestamps and ISO 8601 strings.
    # Supports: GNU date (Linux/WSL/Git Bash), BSD date (macOS), and a pure-bash
    # fallback for minimal environments where neither works.
    local epoch
    if [[ "$resets_at" =~ ^[0-9]+$ ]]; then
        epoch="$resets_at"
    else
        # ISO 8601 string (e.g. "2026-04-14T22:00:00Z")
        # Try GNU date first (-d), then BSD date (-jf), then parse manually
        epoch=$(date -d "$resets_at" +%s 2>/dev/null) \
            || epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$resets_at" +%s 2>/dev/null) \
            || epoch=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$resets_at" +%s 2>/dev/null) \
            || {
                # Pure-bash fallback: parse ISO 8601 via awk + date -u
                # Handles "2026-04-14T22:00:00Z" and "2026-04-14T22:00:00+00:00"
                epoch=$(echo "$resets_at" | awk -F'[T:.Z+-]' '{
                    if (NF >= 6) printf "%s-%s-%s %s:%s:%s UTC\n", $1,$2,$3,$4,$5,$6
                }' | xargs -I{} date -d "{}" +%s 2>/dev/null) || return
            }
    fi

    (( epoch <= 0 )) && return
    local now
    now=$(date +%s)
    local diff=$(( epoch - now ))
    (( diff <= 0 )) && { printf '↺now'; return; }
    local h=$(( diff / 3600 ))
    local m=$(( (diff % 3600) / 60 ))
    if (( h >= 24 )); then
        printf '↺~%dd' "$(( h / 24 ))"
    elif (( h > 0 )); then
        printf '↺~%dh%dm' "$h" "$m"
    else
        printf '↺~%dm' "$m"
    fi
}

truncate_str() {
    local str="$1" max="$2"
    if (( ${#str} > max )); then
        printf '%s…' "${str:0:$((max - 1))}"
    else
        printf '%s' "$str"
    fi
}

make_link() {
    local url="$1" text="$2"
    if $SHOW_CLICKABLE_LINKS && [[ -n "$url" ]]; then
        printf '\033]8;;%s\a%b\033]8;;\a' "$url" "$text"
    else
        printf '%b' "$text"
    fi
}

# ===========================================================================
# Git info with caching
# ===========================================================================

# git@host:owner/repo(.git) | ssh://git@host/owner/repo | https://... -> https://host/owner/repo
_normalize_remote() {
    local url="$1"
    [[ -z "$url" ]] && return
    if [[ "$url" =~ ^ssh://([^@/]+@)?([^/:]+)(:[0-9]+)?/(.+)$ ]]; then
        url="https://${BASH_REMATCH[2]}/${BASH_REMATCH[4]}"
    elif [[ "$url" =~ ^[^@/]+@([^:/]+):(.+)$ ]]; then
        url="https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
    printf '%s' "${url%.git}"
}

# Branch page URL for the repo host (GitLab uses /-/tree/, Bitbucket /src/).
_branch_url() {
    local base="$1" branch="$2"
    [[ -z "$base" ]] && return
    case "$base" in
        *gitlab*)    printf '%s/-/tree/%s' "$base" "$branch" ;;
        *bitbucket*) printf '%s/src/%s'    "$base" "$branch" ;;
        *)           printf '%s/tree/%s'   "$base" "$branch" ;;
    esac
}

get_git_info() {
    local dir="$1"
    # Normalize backslashes (use tr, not ${var//\\//} — fails on MINGW64 piped)
    dir=$(_to_fwd "$dir")
    [[ -z "$dir" || ! -d "$dir" ]] && return

    # WSL2 /mnt/* (9p) hosts make git slow; use the longer TTL there only.
    local ttl=$GIT_CACHE_TTL
    [[ "$dir" == /mnt/* ]] && ttl=$GIT_CACHE_TTL_SLOW

    # "git2-" prefix: the cache no longer stores PR fields (older git-* files had 8 columns).
    local cache_file="" result="" needs_refresh=true
    if [[ -n "$CACHE_ROOT" ]]; then
        local dir_hash
        dir_hash=$(printf '%s' "$dir" | cksum | awk '{print $1}')
        cache_file="${CACHE_ROOT}/git2-${dir_hash}"
        if (( $(_cache_age "$cache_file") < ttl )); then
            IFS= read -r result < "$cache_file" 2>/dev/null
            [[ -n "$result" ]] && needs_refresh=false
        fi
    fi

    if $needs_refresh; then
        local branch dirty="" ahead=0 behind=0 remote_url=""

        branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)
        if [[ -z "$branch" ]]; then
            # Detached HEAD — try to resolve via worktree sibling at same commit
            local _git_dir _common_dir
            _git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
            _common_dir=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)
            if [[ -n "$_git_dir" && -n "$_common_dir" ]]; then
                _git_dir=$(cd "$dir" && cd "$_git_dir" && pwd)
                _common_dir=$(cd "$dir" && cd "$_common_dir" && pwd)
            fi
            if [[ "$_git_dir" != "$_common_dir" ]]; then
                local _my_head _wt_path="" _wt_head="" _wt_branch=""
                _my_head=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
                while IFS= read -r line; do
                    case "$line" in
                        "worktree "*)  _wt_path="${line#worktree }" ;;
                        "HEAD "*)      _wt_head="${line#HEAD }" ;;
                        "branch "*)    _wt_branch="${line#branch refs/heads/}" ;;
                        "")
                            if [[ "$_wt_path" != "$dir" && "$_wt_head" == "$_my_head" && -n "$_wt_branch" ]]; then
                                branch="$_wt_branch"
                                break
                            fi
                            _wt_path="" ; _wt_head="" ; _wt_branch=""
                            ;;
                    esac
                done < <(git -C "$dir" worktree list --porcelain 2>/dev/null; echo "")
            fi
            # Final fallback: short commit hash
            if [[ -z "$branch" ]]; then
                branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
                [[ -z "$branch" ]] && return
                branch="(${branch})"
            fi
        fi

        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
            dirty="dirty"
        else
            dirty="clean"
        fi

        local upstream
        upstream=$(git -C "$dir" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            local ab
            ab=$(git -C "$dir" rev-list --left-right --count "HEAD...${upstream}" 2>/dev/null)
            # ab format: "<ahead>\t<behind>" — split with bash, no awk fork
            read -r ahead behind <<< "$ab"
            ahead="${ahead:-0}"; behind="${behind:-0}"
        fi

        # Remote URL: Claude Code's workspace.repo already names it (any host); only
        # ask git when the payload predates that field. PR data also comes from the
        # JSON (pr.*), so `gh pr view` (~1.5s, network) is no longer needed.
        if [[ -n "$REPO_HOST" && -n "$REPO_OWNER" && -n "$REPO_NAME" ]]; then
            remote_url="https://${REPO_HOST}/${REPO_OWNER}/${REPO_NAME}"
        else
            remote_url=$(_normalize_remote "$(git -C "$dir" remote get-url origin 2>/dev/null)")
        fi

        printf -v result '%s\t%s\t%s\t%s\t%s' "$branch" "$dirty" "${ahead:-0}" "${behind:-0}" "$remote_url"
        [[ -n "$cache_file" ]] && _cache_write "$cache_file" "$result"
    fi

    printf '%s' "$result"
}

# ===========================================================================
# Transcript scan (incremental, cached)
# _tx_last <tag> <grep-line-regex> <grep-P-extract-regex>
# Prints the value from the LAST transcript line matching the regex. The
# transcript only grows, so remember how many bytes were scanned plus the last
# hit, and on the next call scan just the new tail (re-reading 4KB of overlap
# so a line split across two scans is not missed). A shrunk file (rewritten
# transcript) triggers a full backwards scan. Result is cached per session+tag.
# ===========================================================================
_tx_last() {
    local tag="$1" line_re="$2" extract_re="$3"
    local f="$TRANSCRIPT_PATH"
    [[ -n "$f" && -f "$f" ]] || return 0
    local size
    size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null) || return 0
    [[ "$size" =~ ^[0-9]+$ ]] || return 0

    local sid="${SESSION_ID//[^A-Za-z0-9_-]/}"
    local cf="" cs="" cv=""
    if [[ -n "$CACHE_ROOT" ]]; then
        cf="${CACHE_ROOT}/tx-${tag}-${sid:-nosession}"
        if [[ -f "$cf" && ! -L "$cf" ]]; then
            IFS=$'\t' read -r cs cv < "$cf" 2>/dev/null
            # cv is displayed, cs is used in arithmetic: validate both.
            [[ "$cs" =~ ^[0-9]{1,15}$ ]] || { cs=""; cv=""; }
            [[ "$cv" =~ ^[A-Za-z0-9_.-]*$ ]] || cv=""
        fi
    fi

    local hit=""
    if [[ "$cs" =~ ^[0-9]+$ ]] && (( cs == size )); then
        printf '%s' "$cv"; return 0
    elif [[ "$cs" =~ ^[0-9]+$ ]] && (( cs < size )); then
        local start=$(( cs > 4096 ? cs - 4096 : 0 ))
        hit=$(tail -c +$(( start + 1 )) -- "$f" 2>/dev/null | grep -a "$line_re" | tail -n 1 \
              | grep -oP "$extract_re" | head -1 || true)
        [[ -z "$hit" ]] && hit="$cv"
    else
        hit=$(tac -- "$f" 2>/dev/null | grep -a -m1 "$line_re" | grep -oP "$extract_re" | head -1 || true)
    fi
    [[ -n "$cf" ]] && _cache_write "$cf" "$(printf '%s\t%s' "$size" "$hit")"
    printf '%s' "$hit"
}

# ===========================================================================
# Where am I? Anchor + drift marker
# Claude Code's cwd follows the shell (a `cd` inside the session moves it), while
# project_dir is where the session was launched. Showing only the live dir made the
# project vanish behind e.g. ".../.claude/memory". So the display is anchored:
#   ANCHOR_DIR  worktree root when the live dir is inside the worktree, else the
#               project dir (falls back to the live dir on payloads without one)
#   CWD_MARK    live dir relative to the anchor ("" when there is no drift; the
#               absolute ~ path when the live dir left the anchor)
# Git branch / PR / worktree keep following the LIVE dir (they describe where
# commands run), only the path display is anchored.
# ===========================================================================
_trim_slash() { _TS="$1"; [[ "$_TS" != "/" ]] && _TS="${_TS%/}"; return 0; }   # result in _TS
_tilde() {                                                                       # result in _TD
    _TD="$1"
    if [[ "$_TD" == "$HOME" ]]; then _TD="~"
    elif [[ "$_TD" == "$HOME"/* ]]; then _TD="~${_TD#"$HOME"}"; fi
}

_trim_slash "${WORKSPACE_DIR:-${CWD:-$PWD}}"; LIVE_DIR="$_TS"
_trim_slash "$WORKTREE_PATH";                  _WT_NORM="$_TS"
_trim_slash "$PROJECT_DIR";                    _PROJ_NORM="$_TS"
ANCHOR_DIR="$LIVE_DIR"
if [[ -n "$_WT_NORM" && ( "$LIVE_DIR" == "$_WT_NORM" || "$LIVE_DIR" == "$_WT_NORM"/* ) ]]; then
    ANCHOR_DIR="$_WT_NORM"
elif [[ -n "$_PROJ_NORM" && -n "$LIVE_DIR" ]]; then
    ANCHOR_DIR="$_PROJ_NORM"
fi
CWD_MARK=""
if [[ -n "$ANCHOR_DIR" && "$LIVE_DIR" != "$ANCHOR_DIR" ]]; then
    if [[ "$LIVE_DIR" == "$ANCHOR_DIR"/* ]]; then
        CWD_MARK="${LIVE_DIR#"$ANCHOR_DIR"/}"
    else
        _tilde "$LIVE_DIR"; CWD_MARK="$_TD"
    fi
fi
_tilde "$ANCHOR_DIR"; ANCHOR_DISP="$_TD"

_UH_U="${USER:-}";            [[ -z "$_UH_U" ]] && _UH_U=$(id -un 2>/dev/null)
_UH_H="${HOSTNAME%%.*}";      [[ -z "$_UH_H" ]] && _UH_H=$(hostname -s 2>/dev/null)

# _cwd_marker <max-columns>: sets _MARK_TXT to CWD_MARK, left-truncated to fit
# (cut at a "/" when possible: ".claude/memory" -> "…/memory"). Fails when there is
# no marker or no room, so callers print nothing.
_cwd_marker() {
    local max="$1" t
    _MARK_TXT=""
    [[ -n "$CWD_MARK" ]] && (( max >= 1 )) || return 1
    if (( ${#CWD_MARK} <= max )); then
        _MARK_TXT="$CWD_MARK"
    elif (( max == 1 )); then
        _MARK_TXT="…"
    else
        t="${CWD_MARK: -$(( max - 1 ))}"
        if [[ "${CWD_MARK: -$max:1}" != "/" && "$t" == */* ]]; then
            t="/${t#*/}"; [[ "$t" == "/" ]] && t="${CWD_MARK: -$(( max - 1 ))}"
        fi
        # A 1-2 character stub ("…ry") says nothing: show a bare ellipsis instead.
        (( ${#t} < 3 )) && t=""
        _MARK_TXT="…${t}"
    fi
    return 0
}

if [[ "${STATUSLINE_DEBUG:-0}" == "1" ]]; then
    printf 'LIVE_DIR=%s ANCHOR_DIR=%s CWD_MARK=%s PROJECT_DIR=%s WORKTREE_PATH=%s\n' \
        "$LIVE_DIR" "$ANCHOR_DIR" "$CWD_MARK" "$PROJECT_DIR" "$WORKTREE_PATH" >> "${HOME}/.claude/statusline-debug.log"
fi

# ===========================================================================
# Element renderers
# ===========================================================================

# user@host[:anchor-path ▸marker]. The path part (PS1-style, SHOW_CWD_PATH) is a "flex"
# segment: assemble_line sets _FLEX_BUDGET to the columns left on the row. The anchor
# path (project / worktree root) is left-truncated (…/tail) to fit, or dropped when
# there is no room; the ▸marker (live dir relative to the anchor) takes whatever is
# left after it and truncates first. When the worktree row already prints the anchor
# path only the marker follows user@host.
render_user_host() {
    printf '\033[01;32m%s@%s\033[00m' "$_UH_U" "$_UH_H"

    $SHOW_CWD_PATH || return 0
    [[ -z "$ANCHOR_DIR" ]] && return 0
    # Columns after user@host; unknown budget (0) means "no room".
    local room=$(( ${_FLEX_BUDGET:-0} - ${#_UH_U} - ${#_UH_H} - 1 )) rest
    if $_wt_row_shown && [[ "$ANCHOR_DIR" == "$_WT_NORM" ]]; then
        rest=$room
    else
        local avail=$(( room - 2 )) p="$ANCHOR_DISP"     # ":" + 1 spare
        (( avail >= 8 )) || return 0
        (( ${#p} > avail )) && p="…${p: -$(( avail - 1 ))}"
        printf ':\033[01;34m%s\033[00m' "$p"
        rest=$(( room - 1 - ${#p} ))
    fi
    _cwd_marker $(( rest - 2 )) || return 0              # " ▸" + text
    printf ' %b▸%s%b' "$C_DIM" "$_MARK_TXT" "$C_RESET"
}

render_model() {
    $SHOW_MODEL || return
    local color="$C_BLUE"
    case "$MODEL_DISPLAY" in
        *Opus*)   color="$C_AMBER" ;;
        *Haiku*)  color="$C_CYAN" ;;
    esac
    local short="$MODEL_DISPLAY"
    short="${short#Claude }"
    # Strip parenthetical suffix like "(1M context)"
    short="${short%% (*}"
    [[ "$TIER" == "narrow" ]] && short="${short// /}"
    printf '%b◆ %s%b' "$color" "$short" "$C_RESET"
    $SHOW_FAST && [[ "$FAST_MODE" == "true" ]] && printf ' %b⚡%b' "$C_YELLOW" "$C_RESET"
    if $SHOW_VERSION && [[ -n "$CC_VERSION" ]]; then
        printf '%b ~ v%s%b' "$C_DIM" "$CC_VERSION" "$C_RESET"
    fi
}

render_tokens() {
    $SHOW_TOKENS || return
    local pct_int="${USED_PCT%.*}"
    pct_int="${pct_int:-0}"
    local bar used_fmt max_fmt pct_c
    bar=$(build_bar "$pct_int" "$_token_bar")
    used_fmt=$(fmt_tokens "$INPUT_TOKENS")
    max_fmt=$(fmt_tokens "$CTX_SIZE")
    pct_c=$(pct_color "$pct_int")
    local out="${bar} ${pct_c}${pct_int}%${C_RESET} ${C_WHITE}${used_fmt}${C_DIM}/${max_fmt}${C_RESET}"
    # Use ⚠️ (U+26A0 + U+FE0F variation selector) for emoji presentation.
    # Bare ⚠ falls back to text presentation and renders as a missing glyph
    # in many Windows fonts (e.g., Git Bash default Lucida Console).
    [[ "$EXCEEDS_200K" == "true" ]] && out+=" ${C_RED}⚠️ ${C_RESET}"
    printf '%b' "$out"
}

render_git() {
    $SHOW_GIT || return
    [[ -z "$CWD" ]] && return

    local git_info
    git_info=$(get_git_info "$CWD")

    local g_branch="" g_dirty="" g_ahead="0" g_behind="0" g_remote=""

    if [[ -n "$git_info" ]]; then
        IFS=$'\t' read -r g_branch g_dirty g_ahead g_behind g_remote <<< "$git_info"
    fi
    # ahead/behind go through (( )): digits only, whatever the cache held.
    [[ "$g_ahead"  =~ ^[0-9]{1,9}$ ]] || g_ahead=0
    [[ "$g_behind" =~ ^[0-9]{1,9}$ ]] || g_behind=0

    # Worktree branch overrides
    [[ -n "$WORKTREE_BRANCH" ]] && g_branch="$WORKTREE_BRANCH"
    [[ -z "$g_branch" ]] && return

    local display_branch
    display_branch=$(truncate_str "$g_branch" "$_branch_max")

    # Clickable branch link -> GitHub tree URL
    local branch_text="${C_BLUE}${display_branch}${C_RESET}"
    if [[ -n "$g_remote" ]]; then
        branch_text=$(make_link "$(_branch_url "$g_remote" "$g_branch")" "${C_BLUE}${display_branch}${C_RESET}")
    fi

    local out="⎇ ${branch_text}"

    # Dirty: ✔ green (clean), 🛠️ yellow (dirty)
    if [[ "$g_dirty" == "dirty" ]]; then
        out+=" ${C_YELLOW}🛠️ ${C_RESET}"
    elif [[ "$g_dirty" == "clean" ]]; then
        out+=" ${C_GREEN}✔${C_RESET}"
    fi

    # Ahead/behind (hidden when zero, skip in narrow)
    if [[ "$TIER" != "narrow" ]]; then
        (( ${g_ahead:-0}  > 0 )) && out+=" ${C_GREEN}↑${g_ahead}${C_RESET}"
        (( ${g_behind:-0} > 0 )) && out+=" ${C_RED}↓${g_behind}${C_RESET}"
    fi

    # PR / merge request from Claude Code's own JSON (pr.*): dim "PR " + yellow
    # clickable "#N" + review state. No gh CLI, no network, GitLab-aware (pr.kind=mr).
    if $SHOW_PR && [[ -n "$PR_NUMBER" ]]; then
        local pr_label="PR"
        [[ "$PR_KIND" == "mr" ]] && pr_label="MR"
        local pr_num_text="${C_YELLOW}#${PR_NUMBER}${C_RESET}"
        if [[ "$PR_URL" == http* ]]; then
            pr_num_text=$(make_link "$PR_URL" "${C_YELLOW}#${PR_NUMBER}${C_RESET}")
        fi
        local pr_text="${C_DIM}${pr_label} ${C_RESET}${pr_num_text}"
        # Review state: ✔ approved, ✗ changes requested, "draft", … pending
        case "$PR_STATE" in
            approved)           pr_text+=" ${C_GREEN}✔${C_RESET}" ;;
            changes_requested)  pr_text+=" ${C_RED}✗${C_RESET}" ;;
            draft)              pr_text+=" ${C_DIM}draft${C_RESET}" ;;
            pending)            pr_text+=" ${C_DIM}…${C_RESET}" ;;
        esac
        out+=" ${TILDE}${pr_text}"
    fi

    printf '%b' "$out"
}

# Folder: anchor (project / worktree root) basename, clickable link reveals the full
# path; a dim ▸marker follows when the live dir has drifted from it (link -> live dir).
# Flex segment: the marker truncates first, then the basename (never below 10 columns).
# Paths are already forward-slashed (Windows backslashes normalised on input).
render_folder() {
    $SHOW_FOLDER || return
    [[ -z "$ANCHOR_DIR" ]] && return
    local base="${ANCHOR_DIR##*/}"
    [[ -z "$base" ]] && return
    local room="${_FLEX_BUDGET:-0}"
    (( room > 0 )) || room=$_folder_max
    (( room < 10 )) && room=10
    local display_name
    display_name=$(truncate_str "$base" "$room")
    # file:// URL — Windows drive paths need three slashes (file:///C:/...)
    local url="file://${ANCHOR_DIR}"
    [[ "$ANCHOR_DIR" =~ ^[A-Za-z]: ]] && url="file:///${ANCHOR_DIR}"
    local out
    out=$(make_link "$url" "${C_WHITE}${display_name}${C_RESET}")
    if _cwd_marker $(( room - ${#display_name} - 2 )); then   # " ▸" + text
        local live_url="file://${LIVE_DIR}"
        [[ "$LIVE_DIR" =~ ^[A-Za-z]: ]] && live_url="file:///${LIVE_DIR}"
        out+=" $(make_link "$live_url" "${C_DIM}▸${_MARK_TXT}${C_RESET}")"
    fi
    printf '%b' "$out"
}

# Combined thinking + effort: 🧠  ◆ thinking ~ ◕ high
render_thinking_effort() {
    ($SHOW_THINKING || $SHOW_EFFORT) || return

    # ── thinking: from JSON thinking.enabled, fall back to preloaded settings cache ──
    local thinking_icon="" thinking_color=""
    if $SHOW_THINKING; then
        local thinking_val="$IS_THINKING"
        if [[ "$thinking_val" == "unknown" && -n "$SETTINGS_THINKING" ]]; then
            thinking_val="$SETTINGS_THINKING"
        fi
        if [[ "$thinking_val" == "true" ]]; then
            thinking_icon="◆"; thinking_color="$C_MAGENTA"
        else
            thinking_icon="◇"; thinking_color="$C_DIM"
        fi
    fi

    # ── effort ──
    #  1. effort.level from the JSON: the live session value, including mid-session
    #     /effort changes (incl. session-only "max") and per-model saved levels.
    #  2. JSON of a current Claude Code but no effort key: the model has no effort
    #     parameter (e.g. Haiku) → show nothing rather than guess.
    #  3. Payloads from older Claude Code: transcript → settings (per-model, then
    #     top-level) → env var.
    local effort_icon="" effort_color="" level=""
    if $SHOW_EFFORT; then
        level="$EFFORT_LEVEL_JSON"
        if [[ -z "$level" && "$MODERN_SCHEMA" != "true" ]]; then
            level=$(_tx_last effort \
                '"content":"<local-command-stdout>[^"]*[Ee]ffort level' \
                '(?:Set effort level to|Effort level set to) \K(low|medium|high|xhigh|max|auto)')
            [[ -z "$level" && -n "$SETTINGS_EFFORT_MODEL" ]] && level="$SETTINGS_EFFORT_MODEL"
            [[ -z "$level" && -n "$SETTINGS_EFFORT_LEVEL" ]] && level="$SETTINGS_EFFORT_LEVEL"
            [[ -z "$level" && -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]] && level="$CLAUDE_CODE_EFFORT_LEVEL"
            [[ -z "$level" && -n "$SETTINGS_EFFORT_ENV" ]] && level="$SETTINGS_EFFORT_ENV"
            [[ -z "$level" ]] && level="auto"
        fi
        # Only plain level names reach the terminal.
        [[ "$level" =~ ^[a-z0-9_-]{1,12}$ ]] || level=""
        if [[ -n "$level" ]]; then
            case "$level" in
                auto)   effort_icon="◎"; effort_color="$C_DIM" ;;
                low)    effort_icon="◔"; effort_color="$C_WHITE" ;;
                medium) effort_icon="◑"; effort_color="$C_WHITE" ;;
                high)   effort_icon="◕"; effort_color="$C_WHITE" ;;
                xhigh)  effort_icon="◉"; effort_color="$C_MAGENTA" ;;
                max)    effort_icon="●"; effort_color="$C_MAGENTA" ;;
                *)      effort_icon="◈"; effort_color="$C_WHITE" ;;   # future level names
            esac
        fi
    fi

    [[ -z "$thinking_icon" && -z "$effort_icon" ]] && return

    # ── render ────────────────────────────────────────────────────────
    printf '🧠 '
    if [[ -n "$thinking_icon" ]]; then
        printf ' %b%s thinking%b' "$thinking_color" "$thinking_icon" "$C_RESET"
    fi
    if [[ -n "$effort_icon" ]]; then
        [[ -n "$thinking_icon" ]] && printf ' %b~%b' "$C_DIM" "$C_RESET"
        printf ' %b%s %s%b' "$effort_color" "$effort_icon" "$level" "$C_RESET"
    fi
}

render_output_style() {
    $SHOW_OUTPUT_STYLE || return
    # Live JSON value first (reflects session state); fall back to preloaded settings.
    local style="$OUTPUT_STYLE"
    [[ -z "$style" && -n "$SETTINGS_OUTPUT_STYLE" ]] && style="$SETTINGS_OUTPUT_STYLE"
    [[ -z "$style" ]] && style="default"
    local icon label label_color="$C_DIM"
    case "$style" in
        [Dd]efault)     icon="⚙️";  label="default" ;;
        [Ee]xplanatory) icon="🔎";  label="explanatory"; label_color="$C_WHITE" ;;
        [Ll]earning)    icon="🎓";  label="learning";     label_color="$C_WHITE" ;;
        *)              icon="⚙️";  label="${style,,}";   label_color="$C_WHITE" ;;
    esac
    printf '%s  %b%s%b' "$icon" "$label_color" "$label" "$C_RESET"
}

render_caveman() {
    $SHOW_CAVEMAN || return
    local flag="$HOME/.claude/.caveman-active"
    [[ -f "$flag" ]] || return
    local mode=""
    # Read first line directly — no cat fork, no tr fork
    IFS= read -r mode < "$flag" 2>/dev/null || mode=""
    # Strip whitespace via bash parameter expansion
    mode="${mode//[[:space:]]/}"
    [[ -z "$mode" ]] && mode="full"
    local icon label
    case "$mode" in
        lite)               icon="◔"; label="caveman:lite" ;;
        full)               icon="◕"; label="caveman" ;;
        ultra)              icon="●"; label="caveman:ultra" ;;
        wenyan-lite)        icon="◔ 文"; label="caveman:wenyan-lite" ;;
        wenyan|wenyan-full) icon="◕ 文"; label="caveman:wenyan" ;;
        wenyan-ultra)       icon="● 文"; label="caveman:wenyan-ultra" ;;
        commit)             icon="✍️"; label="caveman:commit" ;;
        review)             icon="⊙"; label="caveman:review" ;;
        *)                  icon="◕"; label="caveman:${mode}" ;;
    esac
    printf '%s  \033[38;5;172m%s\033[0m' "$icon" "$label"
}

render_agent() {
    $SHOW_AGENT || return
    [[ -z "$AGENT_NAME" ]] && return
    printf '%bagent:%b%s%b' "$C_DIM" "$C_MAGENTA" "$AGENT_NAME" "$C_RESET"
}

render_advisor() {
    $SHOW_ADVISOR || return
    local model=""
    # 1. Most recent /advisor command output in the transcript (session-only).
    #    Incremental + cached: transcripts reach 100MB+, a full scan per render cost ~450ms.
    model=$(_tx_last advisor \
        '"content":"<local-command-stdout>Advisor set to' \
        '(?:Advisor set to )\K\w+')
    [[ -n "$model" ]] && model="${model,,}"
    # 2. Fall back to advisorModel in settings JSON (preloaded cache, persisted default)
    if [[ -z "$model" && -n "$SETTINGS_ADVISOR_MODEL" ]]; then
        model="${SETTINGS_ADVISOR_MODEL,,}"
    fi
    [[ -z "$model" || "$model" == "off" ]] && return
    local color="$C_BLUE"
    case "$model" in
        *opus*)  color="$C_AMBER" ;;
        *haiku*) color="$C_CYAN"  ;;
    esac
    printf '%badvisor:%b%s%b' "$C_DIM" "$color" "$model" "$C_RESET"
}

render_vim() {
    $SHOW_VIM_MODE || return
    [[ -z "$VIM_MODE" ]] && return
    # Documented values: NORMAL, INSERT, VISUAL, "VISUAL LINE"
    local mode_short="${VIM_MODE:0:1}" color="$C_GREEN"
    case "$VIM_MODE" in
        INSERT)        color="$C_YELLOW" ;;
        VISUAL)        color="$C_MAGENTA" ;;
        "VISUAL LINE") mode_short="VL"; color="$C_MAGENTA" ;;
    esac
    printf '%bvim:%b%s%b' "$C_DIM" "$color" "$mode_short" "$C_RESET"
}

# render_version: version is now embedded in render_model (controlled by SHOW_VERSION).
# Kept here for custom layouts that want version as a standalone segment.
render_version() {
    $SHOW_VERSION || return
    [[ -z "$CC_VERSION" ]] && return
    printf '%bv%s%b' "$C_DIM" "$CC_VERSION" "$C_RESET"
}

# L2: s-id and s-name joined with ~
render_session_ids() {
    local parts=()
    if $SHOW_SESSION_ID && [[ -n "$SESSION_ID" ]]; then
        local short_id="${SESSION_ID:0:8}"
        parts+=("$(printf '%bs-id:%b%s%b' "$C_DIM" "$C_WHITE" "$short_id" "$C_RESET")")
    fi
    if $SHOW_SESSION_NAME; then
        if [[ -n "$SESSION_NAME" ]]; then
            # Flex: fit the name into the columns left on the row (fixed part is
            # "s-id:xxxxxxxx ~ s-name:" = 23 columns); no budget set = no truncation.
            local name="$SESSION_NAME"
            if (( ${_FLEX_BUDGET:-0} > 0 )); then
                local name_max=$(( _FLEX_BUDGET - 23 ))
                (( name_max < 8 )) && name_max=8
                name=$(truncate_str "$name" "$name_max")
            fi
            parts+=("$(printf '%bs-name:%b%s%b' "$C_DIM" "$C_WHITE" "$name" "$C_RESET")")
        else
            parts+=("$(printf '%bs-name:--%b' "$C_DIM" "$C_RESET")")
        fi
    fi
    (( ${#parts[@]} == 0 )) && return
    local out="${parts[0]}"
    for (( i = 1; i < ${#parts[@]}; i++ )); do
        out+="${TILDE}${parts[$i]}"
    done
    printf '%b' "$out"
}

# L2: cost group: cost ~ duration ~ +N/-N joined with ~
render_cost_group() {
    $SHOW_COST_GROUP || return
    local parts=()

    # Cost (show -- when $0 or empty)
    local cost_val="$TOTAL_COST"
    local has_cost=false
    if [[ -n "$cost_val" && "$cost_val" != "0" && "$cost_val" != "0.0" ]]; then
        # Use awk only once for both check and format
        local cost_fmt
        cost_fmt=$(awk "BEGIN {v=$cost_val+0; if (v > 0.0001) printf \"\$%.2f\", v; else print \"\"}")
        if [[ -n "$cost_fmt" ]]; then
            has_cost=true
            parts+=("${C_WHITE}${cost_fmt}${C_RESET}")
        fi
    fi
    $has_cost || parts+=("${C_DIM}--${C_RESET}")

    # Duration (show -- when 0 or empty)
    if [[ -n "$TOTAL_DURATION_MS" && "$TOTAL_DURATION_MS" != "0" ]]; then
        local dur
        dur=$(fmt_duration "$TOTAL_DURATION_MS")
        parts+=("${C_WHITE}${dur}${C_RESET}")
    else
        parts+=("${C_DIM}--${C_RESET}")
    fi

    # Lines changed (show -- when 0)
    if (( LINES_ADDED > 0 || LINES_REMOVED > 0 )); then
        parts+=("${C_GREEN}+${LINES_ADDED}${C_RESET}${C_DIM}/${C_RESET}${C_RED}-${LINES_REMOVED}${C_RESET}")
    else
        parts+=("${C_DIM}--${C_RESET}")
    fi

    local out="${C_DIM}cost:${C_RESET} ${parts[0]}"
    for (( i = 1; i < ${#parts[@]}; i++ )); do
        out+="${TILDE}${parts[$i]}"
    done
    printf '%b' "$out"
}

_render_rate() {
    local label="$1" raw_pct="$2" resets_at="$3"
    local pct_int="${raw_pct%.*}"
    pct_int="${pct_int:-0}"
    if (( pct_int < 0 )); then
        printf '%b%s --%b' "$C_DIM" "$label" "$C_RESET"
        return
    fi
    local bar pct_c
    bar=$(build_bar "$pct_int" "$_rate_bar")
    pct_c=$(pct_color "$pct_int")
    local out="${C_DIM}${label}${C_RESET} ${bar} ${pct_c}${pct_int}%${C_RESET}"
    if [[ "$TIER" != "narrow" ]]; then
        local reset_str
        reset_str=$(fmt_reset_time "$resets_at")
        [[ -n "$reset_str" ]] && out+=" ${C_DIM}${reset_str}${C_RESET}"
    fi
    printf '%b' "$out"
}

render_rate_5h() {
    $SHOW_RATE_LIMITS || return
    _render_rate "5h" "$RATE_5H_PCT" "$RATE_5H_RESETS"
}

render_rate_7d() {
    $SHOW_RATE_LIMITS || return
    _render_rate "7d" "$RATE_7D_PCT" "$RATE_7D_RESETS"
}

# Gateway spend limit (rate_limits.spend_limit): only present behind a Claude apps
# gateway with spend limits, so it is invisible for everyone else.
render_spend() {
    $SHOW_SPEND || return
    (( ${SPEND_PCT%.*} >= 0 )) || return
    local out
    out=$(_render_rate "spend" "$SPEND_PCT" "$SPEND_RESETS")
    if [[ -n "$SPEND_USED" && -n "$SPEND_LIMIT" ]]; then
        out+=" ${C_DIM}\$${SPEND_USED}/\$${SPEND_LIMIT}${C_RESET}"
    fi
    printf '%b' "$out"
}

# Prompt cache (prompt_cache.*): warm → hit ratio + time until it goes cold;
# cold → the next request re-caches the conversation. Full tier (>=140 cols) only:
# narrower L2 rows have no room for it. Hidden when the session reports no caching.
render_cache() {
    $SHOW_CACHE || return
    [[ "$PC_PRESENT" == "true" && "$PC_OBSERVED" == "true" ]] || return
    [[ "$TIER" == "full" ]] || return
    local now left=0
    printf -v now '%(%s)T' -1 2>/dev/null || now=$(date +%s)
    [[ "$PC_WARM" == "true" && -n "$PC_EXPIRES" ]] && left=$(( PC_EXPIRES - now ))
    if (( left <= 0 )); then
        printf '%bcache:%b %bcold%b' "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
        return
    fi
    # hit_ratio is a 0..1 fraction; derive whole percent without forking awk.
    local pct="" frac
    case "$PC_HIT" in
        "")        ;;
        1|1.0*)    pct=100 ;;
        *.*)       frac="${PC_HIT#*.}00"; pct=$(( 10#${frac:0:2} )) ;;
        *)         pct=0 ;;
    esac
    local out="${C_DIM}cache:${C_RESET}"
    if [[ -n "$pct" ]]; then
        local c="$C_GREEN"
        (( pct < 80 )) && c="$C_YELLOW"
        (( pct < 50 )) && c="$C_RED"
        out+=" ${c}${pct}%${C_RESET}"
    else
        out+=" ${C_GREEN}warm${C_RESET}"
    fi
    out+=" ${C_DIM}$(fmt_reset_time "$PC_EXPIRES")${C_RESET}"
    printf '%b' "$out"
}

# Worktree: name + path. Branch omitted if it matches the git branch (L1).
# Each element is capped so the whole line fits in one terminal row.
render_worktree() {
    $SHOW_WORKTREE || return
    [[ -z "$WORKTREE_NAME" ]] && return
    # Budget: TERM_WIDTH minus fixed overhead — let path expand to fill available width
    local _wt_budget=$(( TERM_WIDTH ))
    local _wt_half=$(( _wt_budget / 2 ))
    (( _wt_half < 10 )) && _wt_half=10
    local display_name
    display_name=$(truncate_str "$WORKTREE_NAME" "$_wt_half")
    local out="${C_DIM}wt:${C_RESET}"
    out+=" ${C_DIM}name:${C_RESET}${C_CYAN}${display_name}${C_RESET}"

    # Show path
    local display_path
    display_path=$(truncate_str "$WORKTREE_PATH" "$_wt_half")
    out+=" ${C_DIM}- path:${C_RESET}${C_WHITE}${display_path}${C_RESET}"

    # Show branch only if it differs from git branch
    if [[ -n "$WORKTREE_BRANCH" ]]; then
        # Parse git_info TSV once: branch + remote_url. Avoids two `echo|cut` forks.
        local wt_git_info g_branch_from_git="" remote_url=""
        wt_git_info=$(get_git_info "$CWD")
        if [[ -n "$wt_git_info" ]]; then
            local _f2 _f3 _f4
            IFS=$'\t' read -r g_branch_from_git _f2 _f3 _f4 remote_url <<< "$wt_git_info"
        fi
        # Only show branch if it's different from the git branch
        if [[ "$WORKTREE_BRANCH" != "$g_branch_from_git" ]]; then
            local display_branch
            display_branch=$(truncate_str "$WORKTREE_BRANCH" "$_wt_half")
            local branch_text="${C_BLUE}${display_branch}${C_RESET}"
            if [[ -n "$remote_url" ]]; then
                branch_text=$(make_link "$(_branch_url "$remote_url" "$WORKTREE_BRANCH")" "${C_BLUE}${display_branch}${C_RESET}")
            fi
            out+=" ${C_DIM}- branch:${C_RESET}${branch_text}"
        fi
    fi
    printf '%b' "$out"
}

# Combined settings group: settings: thinking~effort~advisor (for L3)
render_settings_group() {
    ($SHOW_THINKING || $SHOW_EFFORT || $SHOW_ADVISOR) || return
    local te_out adv_out
    te_out=$(render_thinking_effort 2>/dev/null)
    adv_out=$(render_advisor 2>/dev/null)
    [[ -z "$te_out" && -z "$adv_out" ]] && return
    local out="${C_DIM}settings:${C_RESET}"
    [[ -n "$te_out" ]] && out+=" ${te_out}"
    if [[ -n "$adv_out" ]]; then
        [[ -n "$te_out" ]] && out+="${TILDE}" || out+=" "
        out+="${adv_out}"
    fi
    printf '%b' "$out"
}

# Combined output group: output: output_style~caveman (for L3)
render_output_group() {
    ($SHOW_OUTPUT_STYLE || $SHOW_CAVEMAN) || return
    local os_out cv_out
    os_out=$(render_output_style 2>/dev/null)
    cv_out=$(render_caveman 2>/dev/null)
    [[ -z "$os_out" && -z "$cv_out" ]] && return
    local out="${C_DIM}output:${C_RESET}"
    [[ -n "$os_out" ]] && out+=" ${os_out}"
    if [[ -n "$cv_out" ]]; then
        [[ -n "$os_out" ]] && out+="${TILDE}" || out+=" "
        out+="${cv_out}"
    fi
    printf '%b' "$out"
}

# ===========================================================================
# Line assembly
# ===========================================================================

# Visible width of a string with ANSI colour / OSC 8 link sequences removed.
# Pure bash (no fork). Result in _VL. Wide glyphs (emoji) count as 1 — callers
# keep a small safety margin.
_vis_len() {
    local t="$1"
    t="${t//$'\033'\[*([0-9;])m/}"
    t="${t//$'\033]8;;'*([!$'\a'])$'\a'/}"
    _VL=${#t}
}

# Flex renderers can shrink to fit the row: the first one on a line is rendered
# LAST, after every other segment's width is known, and handed _FLEX_BUDGET —
# the columns left (TERM_WIDTH minus other segments, separators and a margin
# for double-width glyphs). Without a budget (0) they print their full form.
_FLEX_MARGIN=6
_is_flex() { [[ "$1" == "render_user_host" || "$1" == "render_session_ids" || "$1" == "render_folder" ]]; }

# Columns reserved for "settings: …" + "output: …" when deciding whether user@host:path
# fits on their row. A constant (not the rendered width) so the row count does not flicker
# with effort / advisor changes; if it is a little off, the flex budget still prevents
# overflow (the path truncates), it only shifts when the split happens.
_STATE_RESERVE=80
# ...and for a useful ▸marker ("▸…/memory") beside the path.
_MARK_RESERVE=12

assemble_line() {
    local renderers=("$@")
    local segments=()
    local seg flex=-1

    _FLEX_BUDGET=0
    for renderer in "${renderers[@]}"; do
        if (( flex < 0 )) && _is_flex "$renderer"; then
            flex=${#segments[@]}
            flex_renderer="$renderer"
            segments+=("")
            continue
        fi
        seg=$($renderer)
        [[ -n "$seg" ]] && segments+=("$seg")
    done

    if (( flex >= 0 )); then
        local used=0 n=${#segments[@]} k
        for (( k = 0; k < n; k++ )); do
            (( k == flex )) && continue
            _vis_len "${segments[$k]}"
            used=$(( used + _VL ))
        done
        used=$(( used + 3 * (n - 1) ))   # " | " between segments
        _FLEX_BUDGET=$(( TERM_WIDTH - used - _FLEX_MARGIN ))
        (( _FLEX_BUDGET < 0 )) && _FLEX_BUDGET=0
        seg=$($flex_renderer)
        _FLEX_BUDGET=0
        segments[$flex]="$seg"
    fi

    # Drop empty segments (a flex renderer may legitimately print nothing).
    local out=() i
    for seg in "${segments[@]}"; do
        [[ -n "$seg" ]] && out+=("$seg")
    done
    (( ${#out[@]} == 0 )) && return

    for (( i = 0; i < ${#out[@]}; i++ )); do
        (( i > 0 )) && printf '%b' "$SEP"
        printf '%b' "${out[$i]}"
    done
}

# ===========================================================================
# Line layouts per mode
# ===========================================================================
# L1: model ~ version | tokens | git(branch ✔/🛠️ ↑N↓N) | folder | agent | vim
# L2: s-id ~ s-name | cost: $X ~ duration ~ +N/-N | 5h rate | 7d rate
# L3: worktree (name - path - branch)  -- only when inside a worktree
# L4 (or L3 if no worktree): user@host | settings: thinking~effort~advisor | output: style~caveman

declare -a L1=() L2=() L3=() L4=()

_has_worktree=false
[[ -n "$WORKTREE_NAME" ]] && _has_worktree=true
_wt_row_shown=false   # true when a dedicated worktree row prints the worktree path

case "$STATUSLINE_LINES" in
    1)
        L1=(render_user_host render_model render_tokens render_git render_folder render_settings_group render_output_group render_agent render_vim render_session_ids render_cost_group)
        ;;
    2)
        L1=(render_model render_tokens render_git render_folder render_agent render_vim)
        L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d render_spend render_cache render_user_host render_settings_group render_output_group)
        ;;
    *)
        L1=(render_model render_tokens render_git render_folder render_agent render_vim)
        L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d render_spend render_cache)
        if $_has_worktree; then
            $SHOW_WORKTREE && _wt_row_shown=true
            L3=(render_worktree)
            L4=(render_user_host render_settings_group render_output_group)
        else
            # Stable split: user@host:anchor-path gets its own row when the one-row form
            # (host + anchor path + settings + output) cannot fit. Decided from the ANCHOR
            # path, never the ▸marker, so the row count does not change as you cd around.
            _split_host_row=false
            if $SHOW_CWD_PATH && [[ -n "$ANCHOR_DIR" ]]; then
                _need=$(( ${#_UH_U} + ${#_UH_H} + 2 + ${#ANCHOR_DISP} + 3 + _STATE_RESERVE + _MARK_RESERVE + _FLEX_MARGIN ))
                (( TERM_WIDTH < _need )) && _split_host_row=true
            fi
            if $_split_host_row; then
                L3=(render_user_host)
                L4=(render_settings_group render_output_group)
            else
                L3=(render_user_host render_settings_group render_output_group)
            fi
        fi
        ;;
esac

# ===========================================================================
# Output
# ===========================================================================
(( ${#L1[@]} > 0 )) && assemble_line "${L1[@]}"

if (( ${#L2[@]} > 0 )); then
    printf '\n'
    assemble_line "${L2[@]}"
fi

if (( ${#L3[@]} > 0 )); then
    printf '\n'
    assemble_line "${L3[@]}"
fi

if (( ${#L4[@]} > 0 )); then
    printf '\n'
    assemble_line "${L4[@]}"
fi

exit 0
