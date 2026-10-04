#!/usr/bin/env bash
# tests/run.sh — fixture tests for statusline.sh
#
# Feeds crafted Claude Code JSON to the script in a sandboxed HOME / cache dir
# and asserts on the ANSI-stripped output. No network, no real settings read.
#
#   bash tests/run.sh          # run all
#   bash tests/run.sh -v       # print each rendered output
#
# Requires: bash 4+, jq, git.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${STATUSLINE_UNDER_TEST:-$ROOT/statusline.sh}"
VERBOSE=false
[[ "${1:-}" == "-v" ]] && VERBOSE=true

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
mkdir -p "$HOME/.claude" "$SANDBOX/cache"
unset TERM_PROGRAM WT_SESSION KITTY_PID FORCE_HYPERLINK COLUMNS TERM_WIDTH

# Sandbox settings: top-level effortLevel=high, per-model override=xhigh,
# advisor=opus. Mirrors the real-world shape that exposed the xhigh bug.
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "effortLevel": "high",
  "modelSettings": { "claude-sonnet-5-5": { "effortLevel": "xhigh" } },
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
    LAST_OUT=$(env "$@" HOME="$HOME" STATUSLINE_CACHE_DIR="$SANDBOX/cache" \
        TERM_WIDTH="${TERM_WIDTH_OVERRIDE:-160}" bash "$SCRIPT" <<<"$json" 2>"$LAST_ERR" | strip)
    $VERBOSE && printf '    ┌─\n%s\n    └─\n' "$(sed 's/^/    │ /' <<<"$LAST_OUT")"
}

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n         %s\n' "$1" "$2"; printf '%s\n' "$LAST_OUT" | sed 's/^/         | /'; }

has()  { [[ "$LAST_OUT" == *"$2"* ]] && ok "$1" || bad "$1" "expected to contain: $2"; }
hasnt(){ [[ "$LAST_OUT" != *"$2"* ]] && ok "$1" || bad "$1" "expected NOT to contain: $2"; }
quiet(){ [[ ! -s "$LAST_ERR" ]] && ok "$1" || bad "$1" "stderr: $(cat "$LAST_ERR")"; }
nlines(){ local n; n=$(printf '%s\n' "$LAST_OUT" | grep -c .); [[ "$n" == "$2" ]] && ok "$1" || bad "$1" "expected $2 lines, got $n"; }

echo "── effort / thinking (the xhigh bug) ──"
render '.'
has   "xhigh object renders thinking on + xhigh" "◆ thinking ~ ◉ xhigh"
quiet "no jq/stderr noise on modern payload"
render '.effort.level="max"';              has   "max renders ● max" "● max"
render '.effort.level="low"';              has   "low renders ◔ low" "◔ low"
render '.thinking.enabled=false';          has   "thinking.enabled=false renders off" "◇ thinking"
render '.thinking.enabled=false';          hasnt "thinking.enabled=false is not shown as on" "◆ thinking"
render 'del(.effort)'
hasnt "effort absent (e.g. Haiku) hides effort: no xhigh" "xhigh"
hasnt "effort absent hides effort: no settings 'high'"    "◕ high"
hasnt "effort absent hides effort: no 'auto' placeholder" "auto"
has   "effort absent still shows thinking" "◆ thinking"
render '.effort={}'
hasnt "effort object without level hides effort" "auto"

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
LAST_OUT=$(printf 'not json' | HOME="$HOME" STATUSLINE_CACHE_DIR="$SANDBOX/cache" TERM_WIDTH=160 bash "$SCRIPT" 2>/dev/null | strip)
[[ -n "$LAST_OUT" ]] && ok "garbage stdin still prints something" || bad "garbage stdin still prints something" "empty output"

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
has   "5h/7d rate limits still render" "5h"
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
n=$(grep -o "$WT" <<<"$LAST_OUT" | wc -l)
[[ "$n" == "1" ]] && ok "worktree path not duplicated by cwd on host row" || bad "worktree path not duplicated by cwd on host row" "path appears $n times"

echo "── width ──"
TERM_WIDTH_OVERRIDE=60 render '.'
nlines "narrow tier forces a single line" 1
TERM_WIDTH_OVERRIDE=160 render '.'
nlines "full tier renders 3 lines (non-worktree)" 3
# No visible line may exceed TERM_WIDTH (wide glyph margin allowed: emoji count 2 cols)
maxw=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' <<<"$LAST_OUT")
(( maxw <= 160 )) && ok "no line wider than TERM_WIDTH=160 (max $maxw)" || bad "no line wider than TERM_WIDTH=160" "max line = $maxw"
LAST_OUT=$(base_json | env -u TERM_WIDTH COLUMNS=100 HOME="$HOME" STATUSLINE_CACHE_DIR="$SANDBOX/cache" bash "$SCRIPT" 2>/dev/null | strip)
nlines "COLUMNS env is honoured when TERM_WIDTH unset (compact tier = 3 lines)" 3

echo "── cache hardening (planted files, symlinks, private root) ──"
SEC="$SANDBOX/sec"; mkdir -p "$SEC"
sec_render() {  # sec_render <cache-dir> [ENV=val ...]: render with an explicit cache dir
    local cdir="$1"; shift
    LAST_ERR="$SANDBOX/stderr"
    LAST_OUT=$(base_json | env "$@" HOME="$HOME" STATUSLINE_CACHE_DIR="$cdir" TERM_WIDTH=160 \
        bash "$SCRIPT" 2>"$LAST_ERR" | strip)
}
none() { [[ ! -e "$2" ]] && ok "$1" || bad "$1" "$2 exists"; }

# 1. Planted cache files carrying shell syntax must never execute.
C1="$SEC/c1"; mkdir -p "$C1"; chmod 700 "$C1"
sec_render "$C1"                                   # warm: creates settings2-*, git2-*
EV="\$(touch $SEC/pwn-settings)"
for f in "$C1"/settings2-*; do
    printf 'SETTINGS_EFFORT_LEVEL=%s\nSETTINGS_ADVISOR_MODEL=a[%s]\nBOGUS=%s\n' "$EV" "$EV" "$EV" > "$f"
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
LAST_OUT=$(base_json | env -u TERM_WIDTH -u COLUMNS HOME="$HOME" STATUSLINE_CACHE_DIR="$C1" SEC="$SEC" C1="$C1" SCRIPT="$SCRIPT" \
    bash -c 'printf "%s" "x[\$(touch $SEC/pwn-width)]" > "$C1/width-$$"; bash "$SCRIPT"; true' 2>/dev/null | strip)
none "planted width cache is not evaluated" "$SEC/pwn-width"
[[ -n "$LAST_OUT" ]] && ok "still renders with a hostile width cache" || bad "still renders with a hostile width cache" "empty output"

# 2. A symlink planted at a cache path must not be followed by our writes.
C2="$SEC/c2"; mkdir -p "$C2"; chmod 700 "$C2"
VICTIM="$SEC/victim"; printf 'precious' > "$VICTIM"
sec_render "$C2"
for f in "$C2"/settings2-* "$C2"/git2-*; do rm -f "$f"; ln -s "$VICTIM" "$f"; done
sec_render "$C2"
[[ "$(cat "$VICTIM")" == "precious" ]] && ok "symlink at cache path: target untouched" || bad "symlink at cache path: target untouched" "victim = $(cat "$VICTIM")"
n=0; for f in "$C2"/settings2-* "$C2"/git2-*; do [[ -L "$f" ]] && n=$((n+1)); done
(( n == 0 )) && ok "symlinks at cache paths are replaced by regular files" || bad "symlinks at cache paths are replaced by regular files" "$n symlinks left"
has  "renders normally after symlink replaced" "◉ xhigh"

# 3. A symlinked cache root is refused: output still correct, nothing written through it.
REAL="$SEC/real-root"; mkdir -p "$REAL"; ln -s "$REAL" "$SEC/link-root"
sec_render "$SEC/link-root"
has  "symlinked cache root: still renders" "◉ xhigh"
[[ -z "$(ls -A "$REAL")" ]] && ok "symlinked cache root: nothing written through it" || bad "symlinked cache root: nothing written through it" "$(ls "$REAL")"

# 4. Default location: $XDG_RUNTIME_DIR/claude-statusline, created 0700.
XR="$SEC/xdg"; mkdir -p "$XR"; chmod 700 "$XR"
LAST_OUT=$(base_json | env -u STATUSLINE_CACHE_DIR XDG_RUNTIME_DIR="$XR" HOME="$HOME" TERM_WIDTH=160 bash "$SCRIPT" 2>/dev/null | strip)
mode=$(stat -c %a "$XR/claude-statusline" 2>/dev/null || echo none)
[[ "$mode" == "700" ]] && ok "default cache dir is created 0700 under XDG_RUNTIME_DIR" || bad "default cache dir is created 0700 under XDG_RUNTIME_DIR" "mode=$mode"
[[ -n "$(ls -A "$XR/claude-statusline" 2>/dev/null)" ]] && ok "default cache dir is actually used" || bad "default cache dir is actually used" "empty"

echo
printf 'passed: %d  failed: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
