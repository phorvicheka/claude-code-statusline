# Rate Limit Data Freshness

## Problem

The 5-hour and 7-day rate limit values shown in the statusline may appear stale compared to Claude Desktop or claude.ai web app.

## Root Cause

The `rate_limits` JSON fields update **only when Claude Code receives an API response** (after each assistant message). There is no background polling. Between interactions -- especially when idle -- the values freeze at whatever the last API response returned.

Claude Desktop and claude.ai query usage endpoints independently and more frequently, which is why they appear more up-to-date.

## Update Triggers

Per the [official docs](https://code.claude.com/docs/en/statusline), the statusline script runs:

- After each new assistant message
- When the permission mode changes
- When vim mode toggles

Updates are debounced at 300ms.

## What Doesn't Help

**`refreshInterval`** in settings.json re-runs your script on a timer, but it still receives the **same cached JSON data** from Claude Code. The JSON payload itself is only updated on the triggers listed above. So even with `refreshInterval: 1`, the `rate_limits` values inside the JSON will remain stale between interactions.

## Behavior During Active Use

During active back-and-forth conversation, rate limit values refresh with each Claude response -- frequent enough for practical awareness. The staleness is most noticeable when:

- Claude Code is idle (waiting for user input)
- A subagent is running a long task
- You're reading output without sending new messages

## Alternative: Direct API Polling

Some community statusline scripts bypass the built-in JSON data entirely and call the Anthropic usage API directly using the OAuth token from `~/.claude/.credentials.json`. This gives fresher data (~180-second cache) but has tradeoffs:

- Polling too frequently (below ~180s) can itself trigger rate limiting
- OAuth tokens can expire, causing the display to show 0%
- Adds complexity and external API dependency

Community implementations using this approach:
- [ohugonnot/claude-code-statusline](https://github.com/ohugonnot/claude-code-statusline)
- [jtbr gist](https://gist.github.com/jtbr/4f99671d1cee06b44106456958caba8b)

## Our Decision

We use the built-in `rate_limits` JSON fields. The tradeoff (stale when idle, fresh during active use) is acceptable given the simplicity and zero additional dependencies.

## Upstream Tracking

- [Issue #27915](https://github.com/anthropics/claude-code/issues/27915) -- Expose rate-limit/plan quota in statusLine JSON (50+ upvotes, open)
- [Issue #30341](https://github.com/anthropics/claude-code/issues/30341) -- Built-in status line with rate limit usage bars
- [Issue #20636](https://github.com/anthropics/claude-code/issues/20636) -- Original request to expose rate limit usage

No official fix timeline from Anthropic as of April 2026.
