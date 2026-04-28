#!/usr/bin/env bash
# ~/.claude/statusline.sh — Claude Code Status Line v2
# Multi-line, adaptive-width status line with configurable elements.
#
# References:
#   https://code.claude.com/docs/en/statusline
#   https://github.com/isaacaudet/claude-code-statusline
#   https://github.com/sirmalloc/ccstatusline

set -f  # disable globbing

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
GIT_CACHE_TTL=5         # seconds to cache git status
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
  def s: @sh;
  "MODEL_DISPLAY=" + (.model.display_name // "Unknown" | s),
  "MODEL_ID=" + (.model.id // "" | s),
  "CWD=" + (.cwd // "" | s),
  "WORKSPACE_DIR=" + (.workspace.current_dir // "" | s),
  "PROJECT_DIR=" + (.workspace.project_dir // "" | s),
  "SESSION_ID=" + (.session_id // "" | s),
  "SESSION_NAME=" + (.session_name // "" | s),
  "VIM_MODE=" + (.vim.mode // "" | s),
  "AGENT_NAME=" + (.agent.name // "" | s),
  "WORKTREE_NAME=" + (.worktree.name // "" | s),
  "WORKTREE_PATH=" + (.worktree.path // "" | s),
  "WORKTREE_BRANCH=" + (.worktree.branch // "" | s),
  "CC_VERSION=" + (.version // "" | s),
  "CTX_SIZE=" + (.context_window.context_window_size // 0 | tostring),
  "USED_PCT=" + (.context_window.used_percentage // 0 | tostring),
  "INPUT_TOKENS=" + (
    if .context_window.current_usage != null then
      ((.context_window.current_usage.input_tokens // 0)
       + (.context_window.current_usage.cache_creation_input_tokens // 0)
       + (.context_window.current_usage.cache_read_input_tokens // 0))
    else
      (.context_window.total_input_tokens // 0)
    end | tostring
  ),
  "EXCEEDS_200K=" + (.exceeds_200k_tokens // .context_window.exceeds_200k_tokens // false | tostring),
  "TOTAL_COST=" + (.cost.total_cost_usd // 0 | tostring),
  "TOTAL_DURATION_MS=" + (.cost.total_duration_ms // 0 | tostring),
  "LINES_ADDED=" + (.cost.total_lines_added // 0 | tostring),
  "LINES_REMOVED=" + (.cost.total_lines_removed // 0 | tostring),
  "RATE_5H_PCT=" + (.rate_limits.five_hour.used_percentage // -1 | tostring),
  "RATE_5H_RESETS=" + (.rate_limits.five_hour.resets_at // "" | tostring | s),
  "RATE_7D_PCT=" + (.rate_limits.seven_day.used_percentage // -1 | tostring),
  "RATE_7D_RESETS=" + (.rate_limits.seven_day.resets_at // "" | tostring | s),
  "OUTPUT_STYLE=" + (.output_style.name // "" | s),
  "IS_THINKING=" + (.is_thinking // .thinking // .alwaysThinkingEnabled // "unknown" | tostring),
  "EFFORT_LEVEL_JSON=" + (.effort_level // .effortLevel // .effort // "" | s),
  "TRANSCRIPT_PATH=" + (.transcript_path // "" | s)
' 2>/dev/null)" || true

# Defaults for unparseable input
: "${MODEL_DISPLAY:=Unknown}" "${CWD:=}" "${CTX_SIZE:=0}" "${USED_PCT:=0}"
: "${INPUT_TOKENS:=0}" "${TOTAL_COST:=0}" "${TOTAL_DURATION_MS:=0}"
: "${LINES_ADDED:=0}" "${LINES_REMOVED:=0}"
: "${RATE_5H_PCT:=-1}" "${RATE_5H_RESETS:=}" "${RATE_7D_PCT:=-1}" "${RATE_7D_RESETS:=}"
: "${OUTPUT_STYLE:=}" "${IS_THINKING:=unknown}"
: "${EFFORT_LEVEL_JSON:=}" "${TRANSCRIPT_PATH:=}"

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

    # This IS a linked worktree — populate name, path, branch
    WORKTREE_NAME="${dir##*/}"
    WORKTREE_PATH="$dir"

    # Find branch: check if any worktree at this path has a branch
    local wt_path="" wt_branch=""
    while IFS= read -r line; do
        case "$line" in
            "worktree "*)  wt_path="${line#worktree }" ;;
            "branch "*)    wt_branch="${line#branch refs/heads/}" ;;
            "")
                if [[ "$wt_path" == "$dir" && -n "$wt_branch" ]]; then
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
                    if [[ "$wt_path" != "$dir" && "$wt_head" == "$my_head" && -n "$wt_branch" ]]; then
                        WORKTREE_BRANCH="$wt_branch"
                        return
                    fi
                    wt_path="" ; wt_head="" ; wt_branch=""
                    ;;
            esac
        done < <(git -C "$dir" worktree list --porcelain 2>/dev/null; echo "")
    fi
}

if [[ -z "$WORKTREE_NAME" ]]; then
    _detect_worktree "$(_to_fwd "${CWD:-$WORKSPACE_DIR}")"
fi

# ===========================================================================
# Terminal width detection
# When run as a statusline command, stdin is a JSON pipe — there is no TTY.
# Tools like tput/stty return bogus defaults (80) in that context.
# Only trust detection when stdout is a real terminal; otherwise default
# to 200 (full tier) and let Claude Code handle display wrapping.
# Override: set TERM_WIDTH in the statusLine command or env.
# ===========================================================================
if [[ "${TERM_WIDTH:-0}" -le 0 ]] 2>/dev/null; then
    if [[ "${COLUMNS:-0}" -gt 0 ]] 2>/dev/null; then
        TERM_WIDTH=$COLUMNS
    elif [[ -t 1 ]]; then
        # stdout is a terminal — detection is trustworthy
        _w=$(tput cols 2>/dev/null) \
            || _w=$(stty size </dev/tty 2>/dev/null | awk '{print $2}') \
            || _w=$(mode con 2>/dev/null | awk '/Columns:/{gsub(/[^0-9]/,"",$2); print $2}') \
            || _w=0
        [[ "${_w:-0}" -gt 0 ]] 2>/dev/null && TERM_WIDTH=$_w || TERM_WIDTH=200
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
        unset _w
    fi
fi

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
# Fixed L1 overhead ≈ 70 chars (model + seps + tokens + git-prefix + dirty-indicator).
_folder_max=$(( TERM_WIDTH - 70 - _branch_max ))
(( _folder_max < 10 )) && _folder_max=10

if [[ "${STATUSLINE_DEBUG:-0}" == "1" ]]; then
    printf 'TERM_WIDTH=%s TIER=%s _branch_max=%s _folder_max=%s\n' \
        "$TERM_WIDTH" "$TIER" "$_branch_max" "$_folder_max" \
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
GIT_CACHE_DIR="/tmp/claude-statusline"

get_git_info() {
    local dir="$1"
    # Normalize backslashes (use tr, not ${var//\\//} — fails on MINGW64 piped)
    dir=$(_to_fwd "$dir")
    [[ -z "$dir" || ! -d "$dir" ]] && return

    mkdir -p "$GIT_CACHE_DIR" 2>/dev/null

    local dir_hash
    dir_hash=$(printf '%s' "$dir" | cksum | awk '{print $1}')
    local cache_file="${GIT_CACHE_DIR}/git-${dir_hash}"

    local needs_refresh=true
    if [[ -f "$cache_file" ]]; then
        local mtime now age
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$(( now - mtime ))
        (( age < GIT_CACHE_TTL )) && needs_refresh=false
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
            ahead=$(echo "$ab" | awk '{print $1}')
            behind=$(echo "$ab" | awk '{print $2}')
        fi

        remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null)
        remote_url="${remote_url/git@github.com:/https:\/\/github.com\/}"
        remote_url="${remote_url%.git}"

        # PR number + merge status via gh CLI (gracefully skip if gh not available)
        local pr_number="" pr_url="" pr_mergeable=""
        if command -v gh >/dev/null 2>&1; then
            local pr_json
            pr_json=$(cd "$dir" && gh pr view --json number,url,mergeable 2>/dev/null)
            if [[ -n "$pr_json" ]]; then
                pr_number=$(printf '%s' "$pr_json" | jq -r '.number // empty' 2>/dev/null)
                pr_url=$(printf '%s' "$pr_json" | jq -r '.url // empty' 2>/dev/null)
                pr_mergeable=$(printf '%s' "$pr_json" | jq -r '.mergeable // empty' 2>/dev/null)
            fi
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$branch" "$dirty" "${ahead:-0}" "${behind:-0}" "$remote_url" "${pr_number:-}" "${pr_url:-}" "${pr_mergeable:-}" > "$cache_file"
    fi

    cat "$cache_file" 2>/dev/null
}

# ===========================================================================
# Element renderers
# ===========================================================================

render_user_host() {
    printf '\033[01;32m%s@%s\033[00m' "$(whoami)" "$(hostname -s)"
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

    local g_branch="" g_dirty="" g_ahead="0" g_behind="0" g_remote="" g_pr_num="" g_pr_url="" g_pr_merge=""

    if [[ -n "$git_info" ]]; then
        IFS=$'\t' read -r g_branch g_dirty g_ahead g_behind g_remote g_pr_num g_pr_url g_pr_merge <<< "$git_info"
    fi

    # Worktree branch overrides
    [[ -n "$WORKTREE_BRANCH" ]] && g_branch="$WORKTREE_BRANCH"
    [[ -z "$g_branch" ]] && return

    local display_branch
    display_branch=$(truncate_str "$g_branch" "$_branch_max")

    # Clickable branch link -> GitHub tree URL
    local branch_text="${C_BLUE}${display_branch}${C_RESET}"
    if [[ -n "$g_remote" ]]; then
        branch_text=$(make_link "${g_remote}/tree/${g_branch}" "${C_BLUE}${display_branch}${C_RESET}")
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

    # PR number with merge status indicator: dim "PR " + yellow clickable "#N"
    if $SHOW_PR && [[ -n "$g_pr_num" ]]; then
        local pr_num_text="${C_YELLOW}#${g_pr_num}${C_RESET}"
        if [[ -n "$g_pr_url" ]]; then
            pr_num_text=$(make_link "$g_pr_url" "${C_YELLOW}#${g_pr_num}${C_RESET}")
        fi
        local pr_text="${C_DIM}PR ${C_RESET}${pr_num_text}"
        # Merge status: ✔ green (mergeable), ✗ red (conflicting)
        case "${g_pr_merge}" in
            MERGEABLE)   pr_text+=" ${C_GREEN}✔${C_RESET}" ;;
            CONFLICTING) pr_text+=" ${C_RED}✗${C_RESET}" ;;
        esac
        out+=" ${TILDE}${pr_text}"
    fi

    printf '%b' "$out"
}

# Folder: show basename, clickable link reveals full path
# Handles Windows backslash paths (e.g. C:\Users\foo\project) by normalizing
# separators before extracting the basename.
render_folder() {
    $SHOW_FOLDER || return
    local dir="${WORKSPACE_DIR:-${CWD:-$PWD}}"
    [[ -z "$dir" ]] && return
    # Normalize backslashes (use tr, not ${var//\\//} — fails on MINGW64 piped)
    local norm
    norm=$(_to_fwd "$dir")
    # Strip trailing separator(s)
    norm="${norm%/}"
    local basename="${norm##*/}"
    [[ -z "$basename" ]] && return
    local display_name
    display_name=$(truncate_str "$basename" "$_folder_max")
    # file:// URL — Windows drive paths need three slashes (file:///C:/...)
    local file_url="file://${norm}"
    [[ "$norm" =~ ^[A-Za-z]: ]] && file_url="file:///${norm}"
    local folder_text
    folder_text=$(make_link "$file_url" "${C_WHITE}${display_name}${C_RESET}")
    printf '%b' "$folder_text"
}

# Combined thinking + effort: 🧠  ◆ thinking ~ ◕ high
render_thinking_effort() {
    ($SHOW_THINKING || $SHOW_EFFORT) || return

    # ── thinking: from JSON IS_THINKING, fall back to settings files ──
    local thinking_icon="" thinking_color=""
    if $SHOW_THINKING; then
        local thinking_val="$IS_THINKING"
        if [[ "$thinking_val" == "unknown" ]]; then
            for f in "${CWD}/.claude/settings.local.json" "${HOME}/.claude/settings.local.json" \
                      "${CWD}/.claude/settings.json"       "${HOME}/.claude/settings.json"; do
                [[ -f "$f" ]] || continue
                thinking_val=$(jq -r 'if has("alwaysThinkingEnabled") then (.alwaysThinkingEnabled | tostring) else empty end' "$f" 2>/dev/null)
                [[ -n "$thinking_val" ]] && break
            done
        fi
        if [[ "$thinking_val" == "true" ]]; then
            thinking_icon="◆"; thinking_color="$C_MAGENTA"
        else
            thinking_icon="◇"; thinking_color="$C_DIM"
        fi
    fi

    # ── effort: JSON field → transcript → settings → env var ──
    local effort_icon="" effort_color="" level=""
    if $SHOW_EFFORT; then
        # 1. JSON field from Claude Code (future-proof: not yet in schema)
        level="$EFFORT_LEVEL_JSON"
        # 2. Parse transcript JSONL for most recent /effort command output
        #    Needed because "max" is session-only and never written to settings.json.
        #    Only match <local-command-stdout> lines to avoid false positives from
        #    agent output that might quote the effort text.
        if [[ -z "$level" && -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
            # Match only direct command output (content starts with the tag),
            # not quoted text inside tool results or agent messages.
            level=$(tac "$TRANSCRIPT_PATH" 2>/dev/null \
                | grep -m1 '"content":"<local-command-stdout>[^"]*[Ee]ffort level' \
                | grep -oP '(?:Set effort level to|Effort level set to) \K(low|medium|high|xhigh|max|auto)' \
                | head -1 || true)
        fi
        # 3. effortLevel key in settings JSON (persisted default)
        if [[ -z "$level" ]]; then
            for f in "${CWD}/.claude/settings.local.json" "${HOME}/.claude/settings.local.json" \
                      "${CWD}/.claude/settings.json"       "${HOME}/.claude/settings.json"; do
                [[ -f "$f" ]] || continue
                level=$(jq -r 'if has("effortLevel") then .effortLevel else empty end' "$f" 2>/dev/null)
                [[ -n "$level" ]] && break
            done
        fi
        # 4. Fall back to CLAUDE_CODE_EFFORT_LEVEL env var
        if [[ -z "$level" && -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]]; then
            level="$CLAUDE_CODE_EFFORT_LEVEL"
        fi
        # 5. Fall back to env var defined in settings.json env blocks
        if [[ -z "$level" ]]; then
            for f in "${CWD}/.claude/settings.local.json" "${HOME}/.claude/settings.local.json" \
                      "${CWD}/.claude/settings.json"       "${HOME}/.claude/settings.json"; do
                [[ -f "$f" ]] || continue
                level=$(jq -r '.env.CLAUDE_CODE_EFFORT_LEVEL // empty' "$f" 2>/dev/null)
                [[ -n "$level" ]] && break
            done
        fi
        [[ -z "$level" ]] && level="auto"
        case "$level" in
            auto)   effort_icon="◎"; effort_color="$C_DIM" ;;
            low)    effort_icon="◔"; effort_color="$C_WHITE" ;;
            medium) effort_icon="◑"; effort_color="$C_WHITE" ;;
            high)   effort_icon="◕"; effort_color="$C_WHITE" ;;
            xhigh)  effort_icon="◉"; effort_color="$C_MAGENTA" ;;
            max)    effort_icon="●"; effort_color="$C_MAGENTA" ;;
            *)      effort_icon="◎"; effort_color="$C_DIM"; level="auto" ;;
        esac
    fi

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
    # Use live JSON OUTPUT_STYLE first (always reflects session state)
    local style="$OUTPUT_STYLE"
    # Fall back to settings.local.json if JSON has no value
    if [[ -z "$style" ]]; then
        for f in "${CWD}/.claude/settings.local.json" "${HOME}/.claude/settings.local.json"; do
            [[ -f "$f" ]] || continue
            local v
            v=$(jq -r 'if has("outputStyle") then .outputStyle else empty end' "$f" 2>/dev/null)
            [[ -n "$v" ]] && style="$v" && break
        done
    fi
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
    local mode
    mode=$(cat "$flag" 2>/dev/null | tr -d '[:space:]')
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
    # 1. Parse transcript for most recent /advisor command output (session-only)
    if [[ -z "$model" && -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
        model=$(tac "$TRANSCRIPT_PATH" 2>/dev/null \
            | grep -m1 '"content":"<local-command-stdout>Advisor set to' \
            | grep -oP '(?:Advisor set to )\K\w+' \
            | head -1 || true)
        [[ -n "$model" ]] && model="${model,,}"
    fi
    # 2. Fall back to advisorModel in settings JSON (persisted default)
    if [[ -z "$model" ]]; then
        for f in "${CWD}/.claude/settings.local.json" "${HOME}/.claude/settings.local.json" \
                  "${CWD}/.claude/settings.json"       "${HOME}/.claude/settings.json"; do
            [[ -f "$f" ]] || continue
            local v
            v=$(jq -r 'if has("advisorModel") then .advisorModel else empty end' "$f" 2>/dev/null)
            [[ -n "$v" ]] && model="${v,,}" && break
        done
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
    local mode_short="${VIM_MODE:0:1}"
    local color="$C_GREEN"
    [[ "$VIM_MODE" == "INSERT" ]] && color="$C_YELLOW"
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
            parts+=("$(printf '%bs-name:%b%s%b' "$C_DIM" "$C_WHITE" "$SESSION_NAME" "$C_RESET")")
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
        local wt_git_info g_branch_from_git=""
        wt_git_info=$(get_git_info "$CWD")
        if [[ -n "$wt_git_info" ]]; then
            g_branch_from_git=$(echo "$wt_git_info" | cut -f1)
        fi
        # Only show branch if it's different from the git branch
        if [[ "$WORKTREE_BRANCH" != "$g_branch_from_git" ]]; then
            local display_branch
            display_branch=$(truncate_str "$WORKTREE_BRANCH" "$_wt_half")
            local branch_text="${C_BLUE}${display_branch}${C_RESET}"
            local remote_url=""
            if [[ -n "$wt_git_info" ]]; then
                remote_url=$(echo "$wt_git_info" | cut -f5)
            fi
            if [[ -n "$remote_url" ]]; then
                branch_text=$(make_link "${remote_url}/tree/${WORKTREE_BRANCH}" "${C_BLUE}${display_branch}${C_RESET}")
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

assemble_line() {
    local renderers=("$@")
    local segments=()
    local seg

    for renderer in "${renderers[@]}"; do
        seg=$($renderer)
        [[ -n "$seg" ]] && segments+=("$seg")
    done

    (( ${#segments[@]} == 0 )) && return

    for (( i = 0; i < ${#segments[@]}; i++ )); do
        (( i > 0 )) && printf '%b' "$SEP"
        printf '%b' "${segments[$i]}"
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

case "$STATUSLINE_LINES" in
    1)
        L1=(render_user_host render_model render_tokens render_git render_folder render_settings_group render_output_group render_agent render_vim render_session_ids render_cost_group)
        ;;
    2)
        L1=(render_model render_tokens render_git render_folder render_agent render_vim)
        L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d render_user_host render_settings_group render_output_group)
        ;;
    *)
        L1=(render_model render_tokens render_git render_folder render_agent render_vim)
        L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d)
        if $_has_worktree; then
            L3=(render_worktree)
            L4=(render_user_host render_settings_group render_output_group)
        else
            L3=(render_user_host render_settings_group render_output_group)
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
