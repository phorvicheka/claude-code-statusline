#!/usr/bin/env bash
# tests/run.sh — fixture tests for statusline.sh
#
# Feeds crafted Claude Code JSON to the script in a sandboxed HOME / cache dir
# and asserts on the ANSI-stripped output. No network, no real settings read.
#
#   bash tests/run.sh          # run all
#   bash tests/run.sh -v       # print each rendered output
#   SUT_BASH=/bin/bash bash tests/run.sh   # run the scripts under test with another bash (macOS 3.2)
#
# Requires: bash 4+, jq, git.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${STATUSLINE_UNDER_TEST:-$ROOT/statusline.sh}"
VERBOSE=false
[[ "${1:-}" == "-v" ]] && VERBOSE=true
SUT_BASH="${SUT_BASH:-bash}"   # interpreter for statusline.sh / install.sh / uninstall.sh
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=true ;; *) IS_WIN=false ;; esac
# Any UTF-8 locale for character counting: C.utf8 on Linux, en_US.UTF-8 on macOS.
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(c|en_us)\.utf-?8$' | head -1)

# Short, symlink-free sandbox: macOS $TMPDIR is long (/var/folders/...) and /var is a symlink to /private/var.
SANDBOX="$(cd "$(mktemp -d /tmp/sl.XXXXXX)" && pwd -P)"
# On Windows, Claude Code sends Windows paths and git prints C:/... ones: use that form throughout.
$IS_WIN && SANDBOX="$(cygpath -m "$SANDBOX")"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
mkdir -p "$HOME/.claude" "$SANDBOX/cache"
unset TERM_PROGRAM WT_SESSION KITTY_PID FORCE_HYPERLINK COLUMNS TERM_WIDTH

# Sandbox settings: top-level effortLevel=high, per-model override=xhigh,
# advisor=opus. Mirrors the real-world shape that exposed the xhigh bug.
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "effortLevel": "high",
  "modelSettings": { "claude-sonnet-5-5": { "effortLevel": "xhigh" },
                     "claude-opus-5-5":   { "autoCompactWindow": 400000 } },
  "advisorModel": "opus"
}
EOF

# A real git repo + linked worktree for worktree / cwd cases.
REPO="$SANDBOX/proj/main-repo"
WT="$SANDBOX/proj/wt-feature"
git init -q -b main "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feature-x "$WT" 2>/dev/null

# Base payload: modern schema (has thinking + fast_mode + workspace.added_dirs).
base_json() {
    jq -n --arg cwd "$REPO" '{
      session_id: "abc12345-0000", transcript_path: "", cwd: $cwd,
      model: {id: "claude-sonnet-5-5", display_name: "Sonnet 5.5"},
      workspace: {current_dir: $cwd, project_dir: $cwd, added_dirs: []},
      version: "2.1.289", output_style: {name: "default"},
      cost: {total_cost_usd: 1.2, total_duration_ms: 60000, total_api_duration_ms: 1000,
             total_lines_added: 5, total_lines_removed: 2},
      context_window: {total_input_tokens: 100000, total_output_tokens: 100,
        context_window_size: 1000000,
        current_usage: {input_tokens: 1, output_tokens: 10, cache_creation_input_tokens: 0, cache_read_input_tokens: 100000},
        used_percentage: 10, remaining_percentage: 90},
      exceeds_200k_tokens: false, fast_mode: false,
      effort: {level: "xhigh"}, thinking: {enabled: true}
    }'
}

strip() { sed -E $'s/\x1b\\[[0-9;]*m//g; s/\x1b\\]8;;[^\x07]*\x07//g'; }

PASS=0; FAIL=0
LAST_OUT=""; LAST_ERR=""

# render <jq-filter> [ENV=val ...]  → sets LAST_OUT (ANSI stripped), LAST_ERR
render() {
    local filter="$1"; shift
    local json
    json=$(base_json | jq -c "$filter")
    LAST_ERR="$SANDBOX/stderr"
    LAST_OUT=$(env "$@" HOME="$HOME" USER=tester HOSTNAME=testhost STATUSLINE_CACHE_DIR="$SANDBOX/cache" \
        TERM_WIDTH="${TERM_WIDTH_OVERRIDE:-160}" "$SUT_BASH" "$SCRIPT" <<<"$json" 2>"$LAST_ERR" | strip)
    $VERBOSE && printf '    ┌─\n%s\n    └─\n' "$(sed 's/^/    │ /' <<<"$LAST_OUT")"
}

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
SKIP=0
skip() { SKIP=$((SKIP+1)); printf '  SKIP %s (%s)\n' "$1" "$2"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n         %s\n' "$1" "$2"; printf '%s\n' "$LAST_OUT" | sed 's/^/         | /'; }

has()  { [[ "$LAST_OUT" == *"$2"* ]] && ok "$1" || bad "$1" "expected to contain: $2"; }
hasnt(){ [[ "$LAST_OUT" != *"$2"* ]] && ok "$1" || bad "$1" "expected NOT to contain: $2"; }
quiet(){ [[ ! -s "$LAST_ERR" ]] && ok "$1" || bad "$1" "stderr: $(cat "$LAST_ERR")"; }
nlines(){ local n; n=$(printf '%s\n' "$LAST_OUT" | grep -c .); [[ "$n" == "$2" ]] && ok "$1" || bad "$1" "expected $2 lines, got $n"; }

echo "── effort / thinking (the xhigh bug) ──"
render '.'
has   "xhigh object renders labelled effort" "effort: ◉ xhigh"
hasnt "thinking on is silent (default state)" "thinking"
quiet "no jq/stderr noise on modern payload"
render '.effort.level="max"';              has   "max renders ● max" "● max"
render '.effort.level="low"';              has   "low renders ◔ low" "◔ low"
render '.thinking.enabled=false';          has   "thinking.enabled=false renders no-think marker" "◇ no-think ~ effort: ◉ xhigh"
render '.thinking.enabled=false';          hasnt "thinking.enabled=false is not shown as on" "◆ thinking"
render 'del(.effort)'
hasnt "effort absent (e.g. Haiku) hides effort: no xhigh" "xhigh"
hasnt "effort absent hides effort: no settings 'high'"    "◕ high"
hasnt "effort absent hides effort: no 'auto' placeholder" "auto"
hasnt "effort absent + thinking on renders no brain block" "🧠"
render 'del(.effort) | .thinking.enabled=false'
has   "effort absent + thinking off still shows no-think" "◇ no-think"
render '.effort={}'
hasnt "effort object without level hides effort" "auto"

echo "── rate limit windows hide when not applicable ──"
render '.rate_limits={five_hour:{used_percentage:38,resets_at:4102444800},seven_day:{used_percentage:18,resets_at:4102444800}}'
has   "both windows present render both" "5h "
has   "7d renders when present" "7d "
render '.rate_limits={seven_day:{used_percentage:18,resets_at:4102444800}}'
hasnt "5h hidden when 7d loaded but no 5h window" "5h "
has   "7d still shown" "7d "
render '.'
has   "no rate_limits yet keeps 5h placeholder" "5h --"
has   "no rate_limits yet keeps 7d placeholder" "7d --"
render '.rate_limits={five_hour:{used_percentage:5,resets_at:4102444800}}'
hasnt "7d hidden when 5h loaded but no 7d window" "7d "
render '.rate_limits={spend_limit:{used_percentage:5,used_usd:1,limit_usd:20,period:"month"}}'
hasnt "7d hidden when only spend limit present" "7d "

echo "── legacy payloads (older Claude Code) ──"
render 'del(.effort,.thinking,.fast_mode) | .effort_level="medium"'
has   "legacy scalar effort_level honoured" "◑ medium"
render 'del(.effort,.thinking,.fast_mode)'
has   "legacy + no JSON effort uses per-model settings (xhigh, not top-level high)" "◉ xhigh"
render 'del(.effort,.thinking,.fast_mode) | .model.id="claude-sonnet-5-5[1m]"'
has   "legacy settings lookup strips [1m] suffix" "◉ xhigh"
render 'del(.effort,.thinking,.fast_mode) | .model.id="claude-haiku-4-5"'
has   "legacy falls back to top-level effortLevel for other models" "◕ high"

echo "── robustness ──"
render '.context_window.used_percentage=null | .context_window.current_usage=null | .context_window.total_input_tokens=null'
has   "null used_percentage/current_usage renders 0%" "0%"
quiet "null context fields: no stderr"
render '.session_name="x$(touch '"$SANDBOX"'/pwned)y'"'"'; echo z"'
[[ ! -e "$SANDBOX/pwned" ]] && ok "hostile session_name is not executed" || bad "hostile session_name is not executed" "pwned file created"
render '.thinking="$(touch '"$SANDBOX"'/pwned2)"'
[[ ! -e "$SANDBOX/pwned2" ]] && ok "hostile scalar thinking is not executed" || bad "hostile scalar thinking is not executed" "pwned2 file created"
LAST_OUT=$(printf 'not json' | HOME="$HOME" STATUSLINE_CACHE_DIR="$SANDBOX/cache" TERM_WIDTH=160 "$SUT_BASH" "$SCRIPT" 2>/dev/null | strip)
[[ -n "$LAST_OUT" ]] && ok "garbage stdin still prints something" || bad "garbage stdin still prints something" "empty output"

echo "── /rename shows at once (custom-title from transcript beats stale JSON) ──"
TXN="$SANDBOX/txn.jsonl"
: > "$TXN"
render ".transcript_path=\"$TXN\" | .session_id=\"rn-sess\" | .session_name=\"old-name\""
has   "no custom-title: JSON session_name used" "s-name:old-name"
printf '{"type":"custom-title","customTitle":"improve-statusline","sessionId":"rn-sess"}\n' >> "$TXN"
render ".transcript_path=\"$TXN\" | .session_id=\"rn-sess\" | .session_name=\"old-name\""
has   "/rename visible before JSON catches up" "s-name:improve-statusline"
printf '{"type":"custom-title","customTitle":"second name","sessionId":"rn-sess"}\n' >> "$TXN"
render ".transcript_path=\"$TXN\" | .session_id=\"rn-sess\" | .session_name=\"old-name\""
has   "later rename wins, spaces kept" "s-name:second name"
render ".transcript_path=\"$TXN\" | .session_id=\"rn-sess\" | .session_name=\"old-name\""
has   "unchanged transcript: cached title still shown" "s-name:second name"

echo "── transcript scan (advisor / legacy effort), incremental cache ──"
TX="$SANDBOX/tx.jsonl"
# The scanner matches the raw JSONL text  "content":"<local-command-stdout>…
raw() { printf '{"type":"system","content":"<local-command-stdout>%s</local-command-stdout>"}\n' "$1"; }
: > "$TX"; raw "Advisor set to Haiku" >> "$TX"
render ".transcript_path=\"$TX\" | .session_id=\"tx-sess-1\""
has   "advisor read from transcript (full scan)" "advisor:haiku"
raw "unrelated output" >> "$TX"; raw "Advisor set to Opus" >> "$TX"
render ".transcript_path=\"$TX\" | .session_id=\"tx-sess-1\""
has   "appended /advisor change picked up (incremental scan)" "advisor:opus"
raw "more unrelated output" >> "$TX"
render ".transcript_path=\"$TX\" | .session_id=\"tx-sess-1\""
has   "later non-matching lines keep last hit" "advisor:opus"
: > "$TX"; raw "Advisor set to Sonnet" >> "$TX"
render ".transcript_path=\"$TX\" | .session_id=\"tx-sess-1\""
has   "rewritten (shrunk) transcript triggers full rescan" "advisor:sonnet"
: > "$TX"; raw "Set effort level to max" >> "$TX"
render ".transcript_path=\"$TX\" | .session_id=\"tx-sess-2\" | del(.effort,.thinking,.fast_mode)"
has   "legacy effort read from transcript (session-only max)" "● max"
render ".transcript_path=\"$TX\" | .session_id=\"tx-sess-3\""
has   "modern payload ignores transcript effort (JSON is live)" "◉ xhigh"
render ".transcript_path=\"/nonexistent/x.jsonl\" | .session_id=\"tx-sess-4\""
has   "missing transcript falls back to settings advisor" "advisor:opus"

echo "── PR badge from JSON (no gh) ──"
mkdir -p "$SANDBOX/bin"; printf '#!/bin/sh\ntouch "%s/gh-called"\nexit 1\n' "$SANDBOX" > "$SANDBOX/bin/gh"; chmod +x "$SANDBOX/bin/gh"
rm -rf "$SANDBOX/cache"; mkdir -p "$SANDBOX/cache"
render '.' PATH="$SANDBOX/bin:$PATH"
[[ ! -e "$SANDBOX/gh-called" ]] && ok "gh CLI is never invoked" || bad "gh CLI is never invoked" "gh-called marker exists"
render '.pr={number:42,url:"https://github.com/o/r/pull/42",review_state:"approved"}'
has   "PR number shown" "PR #42"
has   "approved shows ✔" "PR #42 ✔"
render '.pr={number:42,url:"u",review_state:"changes_requested"}'; has "changes_requested shows ✗" "PR #42 ✗"
render '.pr={number:42,url:"u",review_state:"draft"}';             has "draft shown" "PR #42 draft"
render '.pr={number:42,url:"u",review_state:"pending"}';           has "pending shown" "PR #42 …"
render '.pr={number:7,url:"u",kind:"mr"}';                         has "GitLab MR labelled MR" "MR #7"
render '.';                                                        hasnt "no pr key → no PR badge" "PR #"

echo "── badges: fast mode, prompt cache, spend limit ──"
render '.fast_mode=true';  has   "fast_mode true shows ⚡" "⚡"
render '.fast_mode=false'; hasnt "fast_mode false hides ⚡" "⚡"
NOW=$(date +%s)
render ".prompt_cache={warm:true,caching_observed:true,ttl:\"5m\",expires_at:$((NOW+252)),requests:3,misses:0,hit_ratio:0.97}"
has   "warm prompt cache shown" "cache"
has   "warm prompt cache shows remaining TTL" "4m"
render ".prompt_cache={warm:false,caching_observed:true,ttl:\"5m\",expires_at:null,requests:3,misses:1}"
has   "cold prompt cache shown as cold" "cold"
render '.';                hasnt "no prompt_cache → no cache badge" "cache:"
render ".rate_limits={five_hour:{used_percentage:71,resets_at:$((NOW+3600))},seven_day:{used_percentage:76,resets_at:$((NOW+86400))}}"
has   "5h/7d rate limits still render" "5h "
render ".rate_limits.spend_limit={used_percentage:24,resets_at:$((NOW+86400*3)),used_usd:12.5,limit_usd:50,period:\"weekly\"}"
has   "spend_limit renders" "spend"
has   "spend_limit shows 24%" "24%"

echo "── vim mode ──"
render '.vim={mode:"NORMAL"}';      has "NORMAL → N"  "vim:N"
render '.vim={mode:"INSERT"}';      has "INSERT → I"  "vim:I"
render '.vim={mode:"VISUAL"}';      has "VISUAL → V"  "vim:V"
render '.vim={mode:"VISUAL LINE"}'; has "VISUAL LINE → VL (distinct from VISUAL)" "vim:VL"

echo "── worktree (workspace.git_worktree) + cwd ──"
render ".cwd=\"$WT\" | .workspace.current_dir=\"$WT\" | .workspace.git_worktree=\"wt-feature\""
has   "worktree row shown from workspace.git_worktree" "wt: name:wt-feature"
has   "worktree path shown" "path:$WT"
render '.'
hasnt "main tree: no worktree row" "wt: name:"
render '.'
has   "cwd shown after user@host" "@"
has   "cwd path shown" "$REPO"
render ".cwd=\"$WT\" | .workspace.current_dir=\"$WT\" | .workspace.git_worktree=\"wt-feature\""
n=$(grep -o "$WT" <<<"$LAST_OUT" | wc -l | tr -d " ")
[[ "$n" == "1" ]] && ok "worktree path not duplicated by cwd on host row" || bad "worktree path not duplicated by cwd on host row" "path appears $n times"

echo "── cwd drift: anchor + ▸marker, stable split ──"
MEM="$REPO/.claude/memory"; mkdir -p "$MEM"
at() { printf '.cwd="%s" | .workspace.current_dir="%s"' "$1" "$1"; }   # at <dir> → jq filter
count() { grep -c -- "$1" <<<"$LAST_OUT" || true; }
# widest rendered row among those containing $1 (UTF-8 aware; emoji margin covered by _FLEX_MARGIN)
rowmax() { ( LC_ALL="${UTF8_LOCALE:-C.UTF-8}"; m=0; while IFS= read -r l; do [[ "$l" == *"$1"* ]] && (( ${#l} > m )) && m=${#l}; done <<<"$LAST_OUT"; echo "$m" ); }

render "$(at "$MEM")"
has   "drift: L1 shows project root + ▸subdir"           "main-repo ▸.claude/memory"
[[ "$(count '▸.claude/memory')" == "2" ]] && ok "drift: marker on L1 and on the user@host row" || bad "drift: marker on L1 and on the user@host row" "rows with marker: $(count '▸.claude/memory')"
has   "drift: user@host row shows project path, not the live dir" "$REPO ▸.claude/memory"
hasnt "drift: live dir is not shown as the path"         "$MEM"
nlines "drift: marker does not change the row count (3 at 160 cols)" 3
has   "drift: git branch still follows the live dir"     "⎇ main"
render '.'
hasnt "no drift: no marker"                              "▸"
render "$(at "$REPO")"
hasnt "cwd == project dir: no marker"                    "▸"

mkdir -p "$HOME/notes" "$SANDBOX/elsewhere"
render "$(at "$HOME/notes")"
has   "outside project (under HOME): ▸ + ~ path"         "▸~/notes"
render "$(at "$SANDBOX/elsewhere")"
has   "outside project: ▸ + absolute path"               "▸$SANDBOX/elsewhere"
has   "outside project: L1 still shows the project name" "main-repo ▸"

render "$(at "$MEM") | del(.workspace.project_dir)"
hasnt "legacy payload (no project_dir): no marker"       "▸"
has   "legacy payload: folder is the live basename"      "memory"
render "$(at "$MEM") | del(.workspace)"
hasnt "legacy payload (no workspace): no marker"         "▸"

# Stable split: row count depends on width + anchor path, never on the marker.
TERM_WIDTH_OVERRIDE=225 render "$(at "$MEM")"
nlines "wide terminal: still 3 rows with a marker (225 cols)" 3
TERM_WIDTH_OVERRIDE=225 render '.'
nlines "wide terminal: 3 rows without a marker"           3
TERM_WIDTH_OVERRIDE=120 render "$(at "$MEM")"; r1=$(nlines x 0 >/dev/null; printf '%s\n' "$LAST_OUT" | grep -c .)
TERM_WIDTH_OVERRIDE=120 render '.';           r2=$(printf '%s\n' "$LAST_OUT" | grep -c .)
[[ "$r1" == "$r2" ]] && ok "narrower terminal: marker does not change the row count ($r1 rows both)" || bad "narrower terminal: marker does not change the row count" "with=$r1 without=$r2"
TERM_WIDTH_OVERRIDE=120 render "$(at "$MEM")"
(( $(printf '%s\n' "$LAST_OUT" | grep -c .) == 4 )) && ok "narrower terminal: host row splits out (4 rows)" || bad "narrower terminal: host row splits out (4 rows)" "$(printf '%s\n' "$LAST_OUT" | grep -c .) rows"
has   "split row carries the full anchor path + marker"   "$REPO ▸.claude/memory"
hasnt "split row: path not truncated"                    "…"

# Never wider than the terminal on the rows this feature touches.
LONG="$REPO/$(printf 'deeply-nested-directory-%s/' 1 2 3 4 5 6)final"; mkdir -p "$LONG"
for w in 120 140 160 225; do
    TERM_WIDTH_OVERRIDE=$w render "$(at "$LONG")"
    m=$(rowmax "▸")
    (( m <= w )) && ok "long marker: rows with ▸ fit $w cols (max $m)" || bad "long marker: rows with ▸ fit $w cols" "max row = $m"
done
TERM_WIDTH_OVERRIDE=160 render "$(at "$LONG")"
has   "long marker truncates, keeps the tail"            "▸…"
has   "long marker: basename is never truncated first"   "main-repo ▸"

# _cwd_marker truncation, exercised directly (function extracted from the script).
eval "$(sed -n '/^_cwd_marker() {/,/^}/p' "$SCRIPT")"
# shellcheck disable=SC2034  # CWD_MARK is read by the eval-extracted _cwd_marker
mk() { CWD_MARK="$1"; if _cwd_marker "$2"; then printf '%s' "$_MARK_TXT"; else printf '<none>'; fi; }
[[ "$(mk .claude/memory 14)" == ".claude/memory" ]] && ok "marker fits: shown whole"                        || bad "marker fits: shown whole" "$(mk .claude/memory 14)"
[[ "$(mk .claude/memory 9)"  == "…/memory" ]]       && ok "marker truncation cuts at a slash (…/memory)"    || bad "marker truncation cuts at a slash" "$(mk .claude/memory 9)"
[[ "$(mk .claude/memory 3)"  == "…" ]]              && ok "marker: no 1-2 character stub (bare … instead)"   || bad "marker: no stub" "$(mk .claude/memory 3)"
[[ "$(mk memory 4)"          == "…ory" ]]           && ok "single long component keeps a readable tail"      || bad "single component tail" "$(mk memory 4)"
[[ "$(mk .claude/memory 0)"  == "<none>" ]]         && ok "marker: no room -> nothing printed"               || bad "marker: no room" "$(mk .claude/memory 0)"
[[ "$(mk '' 20)"             == "<none>" ]]         && ok "marker: empty marker -> nothing printed"          || bad "marker: empty" "$(mk '' 20)"

# Worktrees: anchor = worktree root, even from a subdirectory of it.
SUB="$WT/src/api"; mkdir -p "$SUB"
render "$(at "$SUB") | .workspace.git_worktree=\"wt-feature\""
has   "worktree subdir: wt row shows the worktree ROOT"  "path:$WT"
hasnt "worktree subdir: wt row does not show the subdir" "path:$SUB"
has   "worktree subdir: L1 = worktree dir + ▸subdir"     "wt-feature ▸src/api"
n=$(grep -o "$WT" <<<"$LAST_OUT" | wc -l | tr -d " ")
[[ "$n" == "1" ]] && ok "worktree subdir: root path printed once (host row deduped)" || bad "worktree subdir: root path printed once" "appears $n times"
# Captured real payload shape: launched in api-server, cwd inside its .worktrees/ dir.
API="$SANDBOX/ghost/api-server"; GW="$API/.worktrees/feature-2026-04-27-rbac-permissions-authz"
# 225 cols: the wt row caps its path at half the terminal width (pre-existing), and this path is long.
TERM_WIDTH_OVERRIDE=225 render ".cwd=\"$GW\" | .workspace.current_dir=\"$GW\" | .workspace.project_dir=\"$API\" | .workspace.git_worktree=\"feature-2026-04-27-rbac-permissions-authz\""
hasnt "real worktree payload: no marker (cwd is the worktree root)" "▸"
[[ "$(head -1 <<<"$LAST_OUT")" == *"| feature-2026-04-27-rbac-permissions-authz" ]] && ok "real worktree payload: L1 shows the worktree dir" || bad "real worktree payload: L1 shows the worktree dir" "L1 = $(head -1 <<<"$LAST_OUT")"
n=$(grep -o "$GW" <<<"$LAST_OUT" | wc -l | tr -d " ")
[[ "$n" == "1" ]] && ok "real worktree payload: path printed once" || bad "real worktree payload: path printed once" "appears $n times"

echo "── auto-compact limit (autoCompactWindow) ──"
OPUS='.model.id="claude-opus-5-5[1m]" | .model.display_name="Opus 5.5 (1M context)"'
render "$OPUS"
has   "per-model window: rescaled % and ⟲ limit" "25% 100k/⟲400k · 1.0m max"
render '.'
hasnt "unset for this model: today's display" "⟲"
has   "unset for this model: today's display" "10% 100k/1.0m"
render "$OPUS | .context_window.context_window_size=200000"
hasnt "window not below model window: no rescale" "⟲"
TERM_WIDTH_OVERRIDE=80 render "$OPUS"
has   "compact tier keeps ⟲, drops the model-size tail" "100k/⟲400k"
hasnt "compact tier keeps ⟲, drops the model-size tail" "1.0m max"
TERM_WIDTH_OVERRIDE=60 render "$OPUS"
has   "narrow tier keeps ⟲" "/⟲400k"
render "$OPUS | .context_window.current_usage=null"
hasnt "no current_usage (cumulative totals only): no rescale" "⟲"
render "$OPUS" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200k
has   "env CLAUDE_CODE_AUTO_COMPACT_WINDOW beats settings" "50% 100k/⟲200k"
render "$OPUS" CLAUDE_CODE_AUTO_COMPACT_WINDOW=50000
has   "env value below 100k is clamped like CC" "/⟲100k"
render "$OPUS" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
has   "PCT override lowers the trigger point" "/⟲200k"
render "$OPUS" DISABLE_AUTO_COMPACT=1
hasnt "DISABLE_AUTO_COMPACT=1: no rescale" "⟲"
render "$OPUS" DISABLE_COMPACT=1
hasnt "DISABLE_COMPACT=1: no rescale" "⟲"
render "$OPUS" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=08
has   "PCT override with leading zero is decimal, not octal" "/⟲32k"
quiet "PCT override with leading zero: no stderr"
# Project file sets top-level only: it is the highest-priority file setting either key, so it decides.
ACP="$SANDBOX/acproj"; mkdir -p "$ACP/.claude"
echo '{"autoCompactWindow": 327000}' > "$ACP/.claude/settings.json"
render "$OPUS | .cwd=\"$ACP\" | .workspace.current_dir=\"$ACP\" | .workspace.project_dir=\"$ACP\""
has   "project top-level beats user per-model (highest file decides)" "/⟲327k"
render ".cwd=\"$ACP\" | .workspace.current_dir=\"$ACP\" | .workspace.project_dir=\"$ACP\""
has   "top-level fallback for a model without per-model entry" "/⟲327k"
ACS="$SANDBOX/acsame"; mkdir -p "$ACS/.claude"
echo '{"autoCompactWindow": 327000, "modelSettings": {"claude-opus-5-5": {"autoCompactWindow": 250000}}}' > "$ACS/.claude/settings.json"
render "$OPUS | .cwd=\"$ACS\" | .workspace.current_dir=\"$ACS\" | .workspace.project_dir=\"$ACS\""
has   "per-model beats top-level in the same file" "/⟲250k"
# Fresh dir: settings are cached per cwd+model for SETTINGS_CACHE_TTL.
ACO="$SANDBOX/acoff"; mkdir -p "$ACO/.claude"
echo '{"autoCompactWindow": 327000, "autoCompactEnabled": false}' > "$ACO/.claude/settings.json"
render ".cwd=\"$ACO\" | .workspace.current_dir=\"$ACO\" | .workspace.project_dir=\"$ACO\""
hasnt "autoCompactEnabled:false: no rescale" "⟲"
TERM_WIDTH_OVERRIDE=100 render "$OPUS"
maxw=$(LC_ALL="${UTF8_LOCALE:-C.UTF-8}" awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' <<<"$LAST_OUT")
(( maxw <= 100 )) && ok "rescaled tail fits at 100 cols (max $maxw)" || bad "rescaled tail fits at 100 cols" "max line = $maxw"

echo "── width ──"
TERM_WIDTH_OVERRIDE=60 render '.'
nlines "narrow tier forces a single line" 1
TERM_WIDTH_OVERRIDE=160 render '.'
nlines "full tier renders 3 lines (non-worktree)" 3
# No visible line may exceed TERM_WIDTH (wide glyph margin allowed: emoji count 2 cols)
maxw=$(LC_ALL="${UTF8_LOCALE:-C.UTF-8}" awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' <<<"$LAST_OUT")
(( maxw <= 160 )) && ok "no line wider than TERM_WIDTH=160 (max $maxw)" || bad "no line wider than TERM_WIDTH=160" "max line = $maxw"
LAST_OUT=$(base_json | env -u TERM_WIDTH COLUMNS=100 HOME="$HOME" USER=tester HOSTNAME=testhost STATUSLINE_CACHE_DIR="$SANDBOX/cache" "$SUT_BASH" "$SCRIPT" 2>/dev/null | strip)
# At 100 columns user@host:path cannot share a row with settings/output: it splits onto
# its own row (4 rows) instead of dropping the path. At the default width it would be 3.
nlines "COLUMNS env is honoured when TERM_WIDTH unset (100 cols: host row splits, 4 rows)" 4

echo "── cache hardening (planted files, symlinks, private root) ──"
SEC="$SANDBOX/sec"; mkdir -p "$SEC"
sec_render() {  # sec_render <cache-dir> [ENV=val ...]: render with an explicit cache dir
    local cdir="$1"; shift
    LAST_ERR="$SANDBOX/stderr"
    LAST_OUT=$(base_json | env "$@" HOME="$HOME" STATUSLINE_CACHE_DIR="$cdir" TERM_WIDTH=160 \
        "$SUT_BASH" "$SCRIPT" 2>"$LAST_ERR" | strip)
}
none() { [[ ! -e "$2" ]] && ok "$1" || bad "$1" "$2 exists"; }

# 1. Planted cache files carrying shell syntax must never execute.
C1="$SEC/c1"; mkdir -p "$C1"; chmod 700 "$C1"
sec_render "$C1"                                   # warm: creates settings3-*, git2-*
EV="\$(touch $SEC/pwn-settings)"
for f in "$C1"/settings3-*; do
    [[ -e "$f" ]] || { bad "settings cache file exists to plant" "no $C1/settings3-*"; continue; }
    printf 'SETTINGS_EFFORT_LEVEL=%s\nSETTINGS_ADVISOR_MODEL=a[%s]\nSETTINGS_COMPACT_WINDOW=a[%s]\nBOGUS=%s\n' "$EV" "$EV" "$EV" "$EV" > "$f"
done
sec_render "$C1"
none "planted settings cache is not executed" "$SEC/pwn-settings"
for f in "$C1"/git2-*; do printf 'main\t0\ta[$(touch %s/pwn-git)]\tb[$(touch %s/pwn-git)]\t\n' "$SEC" "$SEC" > "$f"; done
sec_render "$C1"
none "planted git cache numbers are not evaluated" "$SEC/pwn-git"
has  "still renders with a hostile git cache" "main-repo"
printf '%s\t%s' 'x[$(touch '"$SEC"'/pwn-tx)]' '$(touch '"$SEC"'/pwn-tx)' > "$C1/tx-advisor-nosession"
sec_render "$C1" 
none "planted transcript cache is not evaluated" "$SEC/pwn-tx"
LAST_OUT=$(base_json | env -u TERM_WIDTH -u COLUMNS HOME="$HOME" STATUSLINE_CACHE_DIR="$C1" SEC="$SEC" C1="$C1" SCRIPT="$SCRIPT" SUT_BASH="$SUT_BASH" \
    "$SUT_BASH" -c 'printf "%s" "x[\$(touch $SEC/pwn-width)]" > "$C1/width-$$"; "$SUT_BASH" "$SCRIPT"; true' 2>/dev/null | strip)
none "planted width cache is not evaluated" "$SEC/pwn-width"
[[ -n "$LAST_OUT" ]] && ok "still renders with a hostile width cache" || bad "still renders with a hostile width cache" "empty output"

# 2. A symlink planted at a cache path must not be followed by our writes.
# Git Bash's ln -s copies instead of linking, so cases 2-3 cannot be set up there.
if $IS_WIN; then
    skip "symlink cases (2, 3)" "Git Bash ln -s copies"
else
C2="$SEC/c2"; mkdir -p "$C2"; chmod 700 "$C2"
VICTIM="$SEC/victim"; printf 'precious' > "$VICTIM"
sec_render "$C2"
for f in "$C2"/settings3-* "$C2"/git2-*; do rm -f "$f"; ln -s "$VICTIM" "$f"; done
sec_render "$C2"
[[ "$(cat "$VICTIM")" == "precious" ]] && ok "symlink at cache path: target untouched" || bad "symlink at cache path: target untouched" "victim = $(cat "$VICTIM")"
n=0; for f in "$C2"/settings3-* "$C2"/git2-*; do [[ -L "$f" ]] && n=$((n+1)); done
(( n == 0 )) && ok "symlinks at cache paths are replaced by regular files" || bad "symlinks at cache paths are replaced by regular files" "$n symlinks left"
has  "renders normally after symlink replaced" "◉ xhigh"

# 3. A symlinked cache root is refused: output still correct, nothing written through it.
REAL="$SEC/real-root"; mkdir -p "$REAL"; ln -s "$REAL" "$SEC/link-root"
sec_render "$SEC/link-root"
has  "symlinked cache root: still renders" "◉ xhigh"
[[ -z "$(ls -A "$REAL")" ]] && ok "symlinked cache root: nothing written through it" || bad "symlinked cache root: nothing written through it" "$(ls "$REAL")"
fi

# 4. Default location: $XDG_RUNTIME_DIR/claude-statusline, created 0700.
XR="$SEC/xdg"; mkdir -p "$XR"; chmod 700 "$XR"
LAST_OUT=$(base_json | env -u STATUSLINE_CACHE_DIR XDG_RUNTIME_DIR="$XR" HOME="$HOME" TERM_WIDTH=160 "$SUT_BASH" "$SCRIPT" 2>/dev/null | strip)
mode=$(stat -c %a "$XR/claude-statusline" 2>/dev/null || stat -f %Lp "$XR/claude-statusline" 2>/dev/null || echo none)
if $IS_WIN; then
    skip "default cache dir is created 0700" "NTFS has no POSIX modes"
else
    [[ "$mode" == "700" ]] && ok "default cache dir is created 0700 under XDG_RUNTIME_DIR" || bad "default cache dir is created 0700 under XDG_RUNTIME_DIR" "mode=$mode"
fi
[[ -n "$(ls -A "$XR/claude-statusline" 2>/dev/null)" ]] && ok "default cache dir is actually used" || bad "default cache dir is actually used" "empty"


echo "── repo reached through a symlinked path is not a worktree ──"
if $IS_WIN; then
    skip "symlinked repo path" "Git Bash ln -s copies"
else
    ln -s "$SANDBOX/proj" "$SANDBOX/proj-link"
    render "$(at "$SANDBOX/proj-link/main-repo/.claude/memory") | del(.workspace)"
    hasnt "symlinked repo path: no worktree row" "wt: name:"
fi

echo "── custom output style label is lowercased (portable _lower, no \${x,,}) ──"
render '.output_style.name="My-Custom_Style2"'
has   "custom output style lowercased" "my-custom_style2"

echo "== portability lint (static: macOS bash 3.2, BSD grep/sed, no tac) =="
# Static evidence only; the macOS CI job runs the scripts under /bin/bash 3.2 for real.
lint() {  # lint <name> <ERE>: fail if any non-comment line of the shipped scripts matches
    local hits
    hits=$(grep -nE -- "$2" "$ROOT/statusline.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
    [[ -z "$hits" ]] && ok "no $1" || { FAIL=$((FAIL+1)); printf '  FAIL no %s\n%s\n' "$1" "$(sed 's/^/         | /' <<<"$hits")"; }
}
lint 'bash-4 case conversion ${x,,} ${x^^}' '\$\{[A-Za-z_][A-Za-z0-9_]*(,,?|\^\^?)\}'
lint 'associative/global/nameref declare' '(declare|local|typeset) +-[a-zA-Z]*[Agn]'
lint 'mapfile/readarray' '\b(mapfile|readarray)\b'
lint '[[ -v ]] tests' '\[\[ +-v '
lint 'negative substring length ${s:0:-1}' '\$\{[A-Za-z_][A-Za-z0-9_]*:[^}]*:-[0-9]'
lint 'grep -P (BSD grep has none)' 'grep +-[a-zA-Z]*P'
lint 'unguarded tac (macOS has none)' '(^|[|;&]|\$\() *tac '
lint 'sed -r (BSD sed needs -E)' 'sed +-[a-zA-Z]*r'

echo "== installers =="
# Each case gets a fresh HOME; installers run without a TTY, as under Claude's Bash tool.
inst() { HOME="$IH" XDG_RUNTIME_DIR='' STATUSLINE_REFRESH_INTERVAL=0 "$SUT_BASH" "$ROOT/install.sh" "$@" </dev/null >/dev/null 2>&1; }
uninst() { HOME="$IH" XDG_RUNTIME_DIR='' "$SUT_BASH" "$ROOT/uninstall.sh" "$@" </dev/null >/dev/null 2>&1; }
fresh() { IH="$SANDBOX/ih-$1"; mkdir -p "$IH/.claude"; }
nbak() { local f n=0; for f in "$IH/.claude/statusline.sh".bak.*; do [[ -f "$f" ]] && n=$((n+1)); done; echo "$n"; }

fresh lines; inst -y -l 2
grep -q 'STATUSLINE_LINES="${STATUSLINE_LINES:-2}"' "$IH/.claude/statusline.sh" && ok "install -l 2 sets 2-line mode" || bad "install -l 2 sets 2-line mode" "line not set"
[[ "$(jq -r .statusLine.command "$IH/.claude/settings.json")" == *statusline.sh ]] && ok "install writes statusLine" || bad "install writes statusLine" "$(cat "$IH/.claude/settings.json")"

fresh badl; inst -y -l 5 && bad "install -l 5 is rejected" "exit 0" || ok "install -l 5 is rejected"
none "install -l 5 writes nothing" "$IH/.claude/statusline.sh"

fresh upd; inst -y; sleep 1; inst -y; sleep 1; inst -y
[[ "$(nbak)" == 0 ]] && ok "re-install keeps no backup of our own script" || bad "re-install keeps no backup of our own script" "$(nbak) backups"
cp "$ROOT/statusline.sh" "$IH/.claude/statusline.sh.bak.1000000000"
uninst -y
none "uninstall after updates removes the script" "$IH/.claude/statusline.sh"
[[ "$(nbak)" == 0 ]] && ok "uninstall drops backups of our own script" || bad "uninstall drops backups of our own script" "$(nbak) left"

fresh foreign; printf '#!/bin/sh\necho mine\n' > "$IH/.claude/statusline.sh"; inst -y; sleep 1; inst -y
[[ "$(nbak)" == 1 ]] && ok "foreign script is backed up once" || bad "foreign script is backed up once" "$(nbak) backups"
uninst -y
grep -q 'echo mine' "$IH/.claude/statusline.sh" 2>/dev/null && ok "uninstall restores the foreign script" || bad "uninstall restores the foreign script" "not restored"
echo
printf 'passed: %d  failed: %d  skipped: %d   (bash under test: %s)\n' "$PASS" "$FAIL" "$SKIP" "$("$SUT_BASH" -c 'echo $BASH_VERSION')"
(( FAIL == 0 ))
