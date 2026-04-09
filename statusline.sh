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
STATUSLINE_LINES="${STATUSLINE_LINES:-2}"  # 1, 2, or 3

# ── Feature toggles (set false to hide any element) ──
SHOW_MODEL=true
SHOW_TOKENS=true
SHOW_GIT=true
SHOW_FOLDER=true
SHOW_THINKING=true
SHOW_AGENT=true
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
GIT_CACHE_TTL=10        # seconds to cache git status
MAX_BRANCH_LEN=40       # truncate branch names beyond this
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
  "EXCEEDS_200K=" + (.exceeds_200k_tokens // false | tostring),
  "TOTAL_COST=" + (.cost.total_cost_usd // 0 | tostring),
  "TOTAL_DURATION_MS=" + (.cost.total_duration_ms // 0 | tostring),
  "LINES_ADDED=" + (.cost.total_lines_added // 0 | tostring),
  "LINES_REMOVED=" + (.cost.total_lines_removed // 0 | tostring),
  "RATE_5H_PCT=" + (.rate_limits.five_hour.used_percentage // -1 | tostring),
  "RATE_5H_RESETS=" + (.rate_limits.five_hour.resets_at // 0 | tostring),
  "RATE_7D_PCT=" + (.rate_limits.seven_day.used_percentage // -1 | tostring),
  "RATE_7D_RESETS=" + (.rate_limits.seven_day.resets_at // 0 | tostring)
' 2>/dev/null)" || true

# Defaults for unparseable input
: "${MODEL_DISPLAY:=Unknown}" "${CWD:=}" "${CTX_SIZE:=0}" "${USED_PCT:=0}"
: "${INPUT_TOKENS:=0}" "${TOTAL_COST:=0}" "${TOTAL_DURATION_MS:=0}"
: "${LINES_ADDED:=0}" "${LINES_REMOVED:=0}"
: "${RATE_5H_PCT:=-1}" "${RATE_7D_PCT:=-1}"

# ===========================================================================
# Terminal width detection
# ===========================================================================
if [[ "${TERM_WIDTH:-0}" -le 0 ]] 2>/dev/null; then
    if [[ "${COLUMNS:-0}" -gt 0 ]] 2>/dev/null; then
        TERM_WIDTH=$COLUMNS
    else
        _w=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
        [[ "${_w:-0}" -gt 0 ]] 2>/dev/null && TERM_WIDTH=$_w || TERM_WIDTH=80
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
    wide)    _branch_max=30; _token_bar=8; _rate_bar=8 ;;
    compact) _branch_max=20; _token_bar=6; _rate_bar=6 ;;
    narrow)  _branch_max=12; _token_bar=4; _rate_bar=4 ;;
esac

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
    (( resets_at <= 0 )) && return
    local now
    now=$(date +%s)
    local diff=$(( resets_at - now ))
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
            branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
            [[ -z "$branch" ]] && return
            branch="(${branch})"
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
    local out="${bar} ${pct_c}${pct_int}%${C_RESET} ${C_MAGENTA}${used_fmt}${C_DIM}/${C_RESET}${C_WHITE}${max_fmt}${C_RESET}"
    [[ "$EXCEEDS_200K" == "true" ]] && out+=" ${C_RED}⚠${C_RESET}"
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
    # Cache remote URL for render_worktree to avoid duplicate get_git_info call
    _CACHED_REMOTE="$g_remote"

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

    # Dirty: ✔ green (clean), ⚠ yellow (dirty)
    if [[ "$g_dirty" == "dirty" ]]; then
        out+=" ${C_YELLOW}⚠${C_RESET}"
    elif [[ "$g_dirty" == "clean" ]]; then
        out+=" ${C_GREEN}✔${C_RESET}"
    fi

    # Ahead/behind (hidden when zero, skip in narrow)
    if [[ "$TIER" != "narrow" ]]; then
        (( ${g_ahead:-0}  > 0 )) && out+=" ${C_GREEN}↑${g_ahead}${C_RESET}"
        (( ${g_behind:-0} > 0 )) && out+=" ${C_RED}↓${g_behind}${C_RESET}"
    fi

    # PR number with merge status indicator
    if $SHOW_PR && [[ -n "$g_pr_num" ]]; then
        local pr_text="${C_CYAN}PR#${g_pr_num}${C_RESET}"
        if [[ -n "$g_pr_url" ]]; then
            pr_text=$(make_link "$g_pr_url" "${C_CYAN}PR#${g_pr_num}${C_RESET}")
        fi
        # Merge status: ✔ green (mergeable), ✗ red (conflicting)
        case "${g_pr_merge}" in
            MERGEABLE)   pr_text+=" ${C_GREEN}✔${C_RESET}" ;;
            CONFLICTING) pr_text+=" ${C_RED}✗${C_RESET}" ;;
        esac
        out+=" ${pr_text}"
    fi

    printf '%b' "$out"
}

# Folder: show basename, clickable link reveals full path
render_folder() {
    $SHOW_FOLDER || return
    local dir="${WORKSPACE_DIR:-$CWD}"
    [[ -z "$dir" ]] && return
    local basename="${dir##*/}"
    [[ -z "$basename" ]] && return
    # Clickable: click reveals full path via file:// URL
    local folder_text="${C_WHITE}${basename}${C_RESET}"
    folder_text=$(make_link "file://${dir}" "${C_WHITE}${basename}${C_RESET}")
    printf '%b' "$folder_text"
}

render_thinking() {
    $SHOW_THINKING || return
    # Cache the settings read once per execution
    if [[ -z "${_THINKING_CACHED:-}" ]]; then
        _THINKING_ON=false
        local settings_file="$HOME/.claude/settings.json"
        if [[ -f "$settings_file" ]]; then
            local val
            val=$(jq -r '.alwaysThinkingEnabled // false' "$settings_file" 2>/dev/null)
            [[ "$val" == "true" ]] && _THINKING_ON=true
        fi
        _THINKING_CACHED=1
    fi
    if $_THINKING_ON; then
        printf '%b◆ thinking%b' "$C_MAGENTA" "$C_RESET"
    else
        printf '%b◇ thinking%b' "$C_DIM" "$C_RESET"
    fi
}

render_agent() {
    $SHOW_AGENT || return
    [[ -z "$AGENT_NAME" ]] && return
    printf '%bagent:%b%s%b' "$C_DIM" "$C_MAGENTA" "$AGENT_NAME" "$C_RESET"
}

render_vim() {
    $SHOW_VIM_MODE || return
    [[ -z "$VIM_MODE" ]] && return
    local mode_short="${VIM_MODE:0:1}"
    local color="$C_GREEN"
    [[ "$VIM_MODE" == "INSERT" ]] && color="$C_YELLOW"
    printf '%bvim:%b%s%b' "$C_DIM" "$color" "$mode_short" "$C_RESET"
}

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
            parts+=("${C_DIM}${cost_fmt}${C_RESET}")
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
    if [[ "$TIER" == "full" || "$TIER" == "wide" ]]; then
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

# Worktree: name, path, branch (clickable branch link)
render_worktree() {
    $SHOW_WORKTREE || return
    [[ -z "$WORKTREE_NAME" ]] && return
    local out="${C_DIM}wt:${C_RESET}"
    out+=" ${C_DIM}name:${C_RESET}${C_CYAN}${WORKTREE_NAME}${C_RESET}"
    if [[ -n "$WORKTREE_PATH" ]]; then
        out+=" ${C_DIM}- path:${C_RESET}${C_WHITE}${WORKTREE_PATH}${C_RESET}"
    fi
    if [[ -n "$WORKTREE_BRANCH" ]]; then
        local branch_text="${C_BLUE}${WORKTREE_BRANCH}${C_RESET}"
        # _CACHED_REMOTE is set by render_git (L1 always runs before L3)
        if [[ -n "${_CACHED_REMOTE:-}" ]]; then
            branch_text=$(make_link "${_CACHED_REMOTE}/tree/${WORKTREE_BRANCH}" "${C_BLUE}${WORKTREE_BRANCH}${C_RESET}")
        fi
        out+=" ${C_DIM}- branch:${C_RESET}${branch_text}"
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
# L1: model | tokens | git(branch ✔/⚠ ↑N↓N) | folder | thinking | agent | vim | version
# L2: s-id ~ s-name | cost: $X ~ duration ~ +N/-N | 5h rate | 7d rate
# L3: worktree (name - path - branch)

declare -a L1=() L2=() L3=()

case "$STATUSLINE_LINES" in
    1)
        L1=(render_model render_tokens render_git render_folder render_thinking render_agent render_vim render_version render_session_ids render_cost_group)
        ;;
    2)
        L1=(render_model render_tokens render_git render_folder render_thinking render_agent render_vim render_version)
        L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d)
        ;;
    *)
        L1=(render_model render_tokens render_git render_folder render_thinking render_agent render_vim render_version)
        L2=(render_session_ids render_cost_group render_rate_5h render_rate_7d)
        L3=(render_worktree)
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

exit 0
