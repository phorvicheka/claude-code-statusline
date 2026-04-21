# Claude Code Profile Management

> Manage plugins, skills, and MCP tools by profile to save tokens, reduce context rot,
> and avoid hitting the 5h/7d usage limits.

---

## File Structure

```
claude-profile-management/
├── README.md                        ← this file
├── switch-profile.sh                ← switching script (copy to PATH or use via !)
├── backend/
│   ├── settings.lean.json           ← research / Q&A only
│   ├── settings.artifacts.json      ← STAGE 00-02: explore, design, proposals
│   ├── settings.backend-impl.json   ← STAGE 03-05: full implementation stack
│   └── settings.review.json         ← STAGE 06-07: code review + PR
└── frontend/
    ├── settings.lean.json           ← research / Q&A only
    ├── settings.frontend.json       ← STAGE 08 + frontend project sessions
    └── settings.review.json         ← frontend code review + PR
```

> **Important**: These are template files. Copy the profiles folder to a stable location
> (e.g. `~/.claude/profiles/`) and configure the alias once. See Setup below.

---

## Why This Matters

Every enabled plugin injects its skill definitions into the system prompt at session start.
Cost compounds:

| Problem | Cause | Impact |
|---------|-------|--------|
| **Token burn** | 14+ plugins loaded = ~10k+ tokens before you type a word | Less room for actual work |
| **Context rot** | Stale plugin instructions crowd out working context | Claude drifts, forgets recent edits |
| **Faster usage exhaustion** | Each message costs more toward the 5h/7d limit | Fewer messages per reset window |

> **Note**: Project skills in `.claude/skills/` are **always loaded regardless of profile**.
> Profiles only control marketplace plugins (codex, pr-review-toolkit, figma, kotlin-lsp, etc.).
> So `roadmap-phase-processor` and all your local skills always work — even on `lean`.

---

## Switching Profiles — Is It Possible Mid-Session?

**Short answer**: You can trigger the switch inside Claude, but **the new profile takes effect
only after restarting Claude Code**. The restart is not a blocker — `roadmap-phase-processor`
has built-in state detection and resumes from any stage.

### How to switch inside a running Claude session

Use the `!` prefix to run a shell command without leaving the session:

```
! cc-switch artifacts
```

Then exit Claude and restart. On resume, tell roadmap-phase-processor to continue:

```
use claude skill 'roadmap-phase-processor' with --auto --impl-all to Continue Phase X
```

### Switching at stage boundaries (recommended workflow)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Session 1 — cc-switch artifacts → claude                                │
│   "use claude skill 'roadmap-phase-processor' to Process Phase X"       │
│   Works through STAGE 00 (branch), STAGE 01 (explore + Figma),         │
│   STAGE 02 (propose/ff, pre-impl design review)                         │
│                                                                         │
│   At end: ! cc-switch backend-impl → exit Claude                        │
├─────────────────────────────────────────────────────────────────────────┤
│ Session 2 — claude (backend-impl profile)                               │
│   "...to Continue Phase X"                                              │
│   Works through STAGE 03 (impl), STAGE 04 (checks), STAGE 05 (commits) │
│                                                                         │
│   At end: ! cc-switch review → exit Claude                              │
├─────────────────────────────────────────────────────────────────────────┤
│ Session 3 — claude (review profile)                                     │
│   "...to Continue Phase X"                                              │
│   Works through STAGE 06 (parallel review), STAGE 07 (push + PR)       │
│                                                                         │
│   If STAGE 08 needed: ! cc-switch artifacts (figma on) → exit Claude   │
│   Else:               ! cc-switch lean → exit Claude                    │
├─────────────────────────────────────────────────────────────────────────┤
│ Session 4 — claude (lean or artifacts)                                  │
│   "...to Continue Phase X"                                              │
│   Works through STAGE 08 (handoff, optional), STAGE 09 (archive)       │
└─────────────────────────────────────────────────────────────────────────┘
```

### Single-session alternative (simple phases)

For small phases (Rule 1 or Rule 2 classifier), just run `backend-impl` for the entire
phase. The extra token cost is low; the simplicity is worth it.

---

## The 5 Profiles

| Profile | Use When | Plugins active |
|---------|----------|----------------|
| `lean` | Research, Q&A, web search, docs lookup | context7, superpowers |
| `artifacts` | STAGE 00-02: branch, explore, Figma, design, proposals | + figma, document-skills, claude-md-management |
| `backend-impl` | STAGE 03-05: full implementation, checks, commits | ALL (full stack) |
| `review` | STAGE 06-07: parallel review, PR creation | code-review, pr-review-toolkit, codex, feature-dev, commit-commands, developer-tools, kotlin-lsp / typescript-lsp |
| `frontend` | STAGE 08 + any frontend project | figma, document-skills, context7, playwright, commit-commands, developer-tools, code-review, frontend-design |

---

## Profile Details

### `lean` — Research / Simple Q&A

**When**: Asking questions, looking up library docs, browsing the web, or quickly checking
something. No coding, no review, no commits.

**Active**: context7 (library docs), superpowers (brainstorming, grill-me, writing-plans)

**Off**: everything else — code-review, pr-review-toolkit, feature-dev, codex,
commit-commands, document-skills, claude-md-management, code-simplifier, figma, playwright,
security-guidance, developer-tools, claude-code-setup, skill-creator, kotlin-lsp / typescript-lsp.

---

### `artifacts` — STAGE 00-02: Branch, Explore, Design, Proposals

**When**: Creating the feature branch, exploring requirements, writing proposals/specs, or doing
the pre-impl design review. STAGE 01 (explore) often needs to inspect **frontend code, Figma
mockup files (if provided), and design assets** alongside backend.

**Active**:
- `context7` — docs lookup during exploration
- `superpowers` — writing-plans, grill-me, brainstorming
- `figma` — read Figma mockup files and inspect design/frontend patterns during STAGE 01 explore
- `document-skills` — create OpenSpec docs, summaries, guides
- `claude-md-management` — update CLAUDE.md files

**Off**: kotlin-lsp, codex, pr-review-toolkit, feature-dev, code-simplifier, playwright,
security-guidance, developer-tools, commit-commands, claude-code-setup, skill-creator.

---

### `backend-impl` — STAGE 03-05: Full Implementation

**When**: Writing code, running tests, fixing issues, committing. This is the heavyweight
profile — every tool is available.

**Active**: ALL plugins — this matches your current global `~/.claude/settings.json` default
plus `kotlin-lsp` from the project settings.

---

### `review` — STAGE 06-07: Parallel Review + PR

**When**: Running codex / feature-dev review agents and creating the PR.

**Active**:
- `code-review` — primary review workflow
- `pr-review-toolkit` — convention gate + test analyzer + silent-failure hunter
- `codex` — codex:codex-rescue parallel reviewer
- `feature-dev` — feature-dev:code-reviewer parallel reviewer
- `commit-commands` — commit-push-pr workflow
- `superpowers` — requesting/receiving code review
- `developer-tools` — git utilities
- `context7` — docs lookup during review
- `kotlin-lsp` (backend) / `typescript-lsp` (frontend) — LSP for code navigation

**Off**: figma, document-skills, playwright, code-simplifier, claude-code-setup,
skill-creator, security-guidance, claude-md-management.

---

### `frontend` — STAGE 08 + Any Frontend Project

**When**: Generating frontend API handoff docs (STAGE 08), or working inside
`ci-telemedicine-doctor-nextjs-front`.

**Active**:
- `figma` — design inspection and component mapping
- `document-skills` — generate handoff docs, specs
- `context7` — Next.js, Tailwind, Prisma docs
- `superpowers` — workflow skills
- `code-review` — frontend code review
- `commit-commands` — commit and PR
- `developer-tools` — git utilities
- `claude-md-management` — CLAUDE.md updates
- `playwright` — e2e test capture and screenshots
- `frontend-design` — enabled here (globally disabled); activates for UI component work
- `typescript-lsp` — TypeScript LSP intelligence

**Off**: kotlin-lsp, codex, pr-review-toolkit, security-guidance, code-simplifier, feature-dev.

---

## Stage → Profile Mapping (roadmap-phase-processor)

| Stage | Name | Profile | Notes |
|-------|------|---------|-------|
| STAGE 00 | Create branch | `lean` | No tools needed except git |
| STAGE 01 | Explore | `artifacts` | May inspect frontend code, Figma mockup files (if provided), and design assets |
| STAGE 02 | Artifacts (propose/ff) | `artifacts` | Writing docs, API design, frontend alignment |
| Pre-Impl HARD GATE | Design review | `artifacts` | API design + frontend-alignment step |
| STAGE 03 | Implementation | `backend-impl` | Full stack — don't cut corners here |
| STAGE 04 | Final checks | `backend-impl` | Gradle + detekt + tests need full tools |
| STAGE 05 | Atomic commits | `review` | Light commit tooling is enough |
| STAGE 06 | Parallel review | `review` | codex + feature-dev + pr-review-toolkit |
| STAGE 07 | Push & PR | `review` | commit-push-pr + ultrareview |
| STAGE 08 | Frontend handoff | `frontend` or `artifacts`* | *use `artifacts` if staying in backend project |
| STAGE 09 | Archive & roadmap | `lean` | opsx:verify/sync/archive = docs only |

---

## Setup

### Step 1 — Copy profiles to a stable location

```bash
cp -r ~/projects/connectedin-telemedicine-springboot-kotlin-api-server/tmp/claude-profile-management \
      ~/.claude/profiles
chmod +x ~/.claude/profiles/switch-profile.sh
```

### Step 2 — Add `cc-switch` alias to `~/.bashrc` or `~/.zshrc`

```bash
# Claude Code profile switcher
cc-switch() {
  bash "$HOME/.claude/profiles/switch-profile.sh" "$@"
}
```

Reload your shell:
```bash
source ~/.bashrc   # or source ~/.zshrc
```

### Step 3 — Verify

```bash
cc-switch --help
```

### Step 4 — Add backup profiles to each project's `.claude/`

Copy the relevant profile files so they're available in each project:

**Backend project** (`connectedin-telemedicine-springboot-kotlin-api-server`):
```bash
cp ~/.claude/profiles/backend/settings.*.json .claude/
```

**Frontend project** (`ci-telemedicine-doctor-nextjs-front`):
```bash
cp ~/.claude/profiles/frontend/settings.*.json .claude/
```

> With profile files in `.claude/`, you can also apply them manually:
> `cp .claude/settings.lean.json .claude/settings.json`

---

## Using the Switch Script

```bash
# Apply a profile (auto-detects backend vs frontend by build.gradle.kts / package.json)
cc-switch lean
cc-switch artifacts
cc-switch backend-impl
cc-switch review
cc-switch frontend

# Apply to a specific project directory
cc-switch lean ~/projects/ci-telemedicine-doctor-nextjs-front

# Inside a Claude Code session (! prefix runs in terminal)
! cc-switch backend-impl
```

The script:
1. Auto-detects project type from `build.gradle.kts` (backend) or `package.json` (frontend)
2. Backs up current `settings.json` → `settings.json.bak`
3. Copies the profile file as the new `settings.json`
4. Prints a restart reminder with the resume command

---

## MCP Tools by Profile

MCP tools also consume tokens. Apply the same principle:

| Profile | Keep | Disable |
|---------|------|---------|
| `lean` | `context7` | `sequential-thinking`, Google Drive |
| `artifacts` | `context7`, `sequential-thinking` | Google Drive |
| `backend-impl` | ALL | — |
| `review` | `context7`, `sequential-thinking` | Google Drive |
| `frontend` | `context7`, `sequential-thinking` | Google Drive |

Disable unused MCP servers globally via `~/.claude/settings.json`:
```json
{
  "disabledMcpjsonServers": ["github", "google-drive"]
}
```

---

## Tips

1. **Start lean, escalate as needed.** Begin every session with `lean` or `artifacts`. Switch to
   `backend-impl` only when you reach STAGE 03. You can switch and restart at any boundary.

2. **Never run `backend-impl` for STAGE 09 archive.** It wastes tokens loading codex,
   pr-review-toolkit, and kotlin-lsp for a task that only moves files and writes docs.

3. **Project skills always load.** `.claude/skills/` contents (including roadmap-phase-processor)
   are always available regardless of which profile is active. Profiles only gate marketplace
   plugins.

4. **`! cc-switch <profile>` inside Claude.** The `!` prefix runs the command in your terminal
   without leaving the Claude session. Use it right before you know a stage boundary is coming,
   then exit and restart.

5. **Check context usage before a long session.** Run `/context` to see current token count.
   If you're above 30% before writing a line of code, switch to a leaner profile and restart.

6. **For STAGE 08 in the backend project**, `artifacts` profile is sufficient — it keeps figma on
   for design inspection and document-skills for generating the handoff doc. Only switch to
   `frontend` if you are actually working in the frontend repo.

7. **The 5h usage limit resets faster with heavy profiles.** Each message with 14+ plugins loaded
   costs more toward your limit than the same message with 2 plugins. Lean sessions extend how
   much actual coding you can do per reset window.
