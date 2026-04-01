# /save-discussion — Save Current Discussion to a Discussion File

Saves the discussion from the current conversation session as a structured discussion document.
**Runs a single sub-agent in the background** so the discussion can continue while saving.

---

## Arguments

| argument | description | default |
|----------|-------------|---------|
| `lang` | output language for the saved discussion file (`ko`, `en`, etc.). The project's CLAUDE.md defines the default | project default |

---

## Main Claude's Role (minimal — return immediately)

### Step 1: Determine Topic Hint

Refer to the table below and determine in 1 line which module the current discussion belongs to.
Decide quickly by keyword matching without deep analysis.

| Module key | Keywords | discussion path | topic log path |
|------------|----------|-----------------|----------------|
| `module_a` | keyword1, keyword2, keyword3 | `research/topics/module_a/discussion/` | `research/topics/module_a/log.md` |
| `module_b` | keyword4, keyword5, keyword6 | `research/topics/module_b/discussion/` | `research/topics/module_b/log.md` |
| `module_c` | keyword7, keyword8 | `research/topics/module_c/discussion/` | `research/topics/module_c/log.md` |
| `meta` | research system, logging, workflow, skill, Claude Code | `research/topics/analysis/discussion/` | (none) |

> **Customize this table** for your project. Replace `module_a`, `module_b`, `module_c` with your actual research modules and their keywords. The `meta` row can be kept as-is for general workflow discussions.

If the discussion spans multiple modules, choose the one with the largest share.

### Step 2: Launch Background Sub-agent

**Call the Agent tool with `run_in_background: true`.**

Compose the prompt in the format below (replace bracketed items with actual values):

```
This is a research discussion file synthesis and saving task.
Perform both file I/O and content synthesis.

## Meta Information

**Today's date**: [YYYY-MM-DD]  (MMDD = [MMDD])
**Language**: [resolved lang value, e.g. Korean / English] — write all content in this language. Technical terms may remain in original language.
**Module**: [wm / critic / replanning / meta]
**discussion path**: [discussion path for this module]
**topic log path**: [topic log path for this module, "none" if not applicable]
**daily log path**: research/logs/[YYYY-MM-DD]/log.md

## Current Session Conversation

The following is the conversation from this session, passed as-is without modification.

---
User: [message]
Claude: [response]
User: [message]
Claude: [response]
(continued...)
---

## Tasks to Perform (in order)

### Step 1: Check File Existence → Determine Mode

Run Glob with pattern `[discussion path][MMDD]_*.md`.
- If file exists: **update mode** — Read it to understand existing content
- If no file: **create mode**

### Step 2: Determine Slug and Filename

Read the conversation and:
- slug: 3-5 kebab-case words capturing the core of the discussion (e.g., `gap-loss-two-pass-decision`)
- filename: `[MMDD]_<slug>.md`
- In update mode, use the existing filename as-is

### Step 3: Save Discussion File

#### Create Mode

If the directory doesn't exist, create it with `mkdir -p`, then Write with the structure below.

\`\`\`markdown
# <title> — <one-line description>
> **Date**: YYYY-MM-DD
> **Topic**: <core question or purpose of the discussion>
> **Conclusion**: <final decision or key insight in 1-2 sentences>
> **Related**: <related file links, if any>

---

## 1. Background

Why this discussion started. The problem to solve, observed phenomena, prior state.

## 2. Core Arguments

Flow of the discussion: question → reasoning → why this direction → intermediate insights.
Include code, formulas, ASCII diagrams if they appeared.

## 3. Rejected Paths

Alternatives that were not adopted:
- **<alternative name>**: <why it was considered> — <why it was rejected>

## 4. Conclusion and Next Steps

Final decisions and derived open questions / next actions.
\`\`\`

Writing principles:
- No conclusion-only summaries — richly describe the details of the reasoning process
- Include in the body any analysis/explanations from Claude that the user responded to
- Preserve numbers, comparisons, and code snippets as-is
- Empty sections may be omitted

#### Update Mode

Compare the existing file content with the current conversation.
Identify only what was added since the last save and apply **only the changed parts** via Edit.

Apply each operation as an independent Edit call in order:

| Operation | Action |
|-----------|--------|
| `APPEND_TO "## N. SectionName"` | Append content to the end of the section (just before next `## `) |
| `REPLACE "## N. SectionName"` | Replace entire section from header to next `## ` (for updatable sections like conclusion) |
| `UPDATE_META` | Replace only the `> **Conclusion**:` line at the top of the file via Edit |
| `ADD_SECTION_AFTER "## N. SectionName"` | Insert a new section block at the end of the section |

Do not touch sections with no changes.

### Step 4: Add Log Links (Create mode only)

> **Sync-safe design**: Log files are written only via Bash `echo >> file` append, without Read.
> Do not use the Read → Edit pattern (prevents conflicts with other operations running in background).

Link text format:
\`\`\`
→ Discussion: [MMDD_slug.md](discussion/MMDD_slug.md) — <one-line title>
\`\`\`

**Daily log** (`research/logs/YYYY-MM-DD/log.md`):
- If file exists: append via `echo "link text" >> [daily log path]` (Bash)
- If file doesn't exist: skip

**Topic log** (when topic log path is not "none"):
- Append via `echo "\n→ Discussion: [link]" >> [topic log path]` (Bash)
- If file doesn't exist: skip

> Content is appended to the end of the file, so it may not be inside a date section. This is an intentional trade-off.
> If precise placement is needed, move it manually after completion.

Skip in update mode.

### Step 5: Completion Report

Report the saved file path and mode (create/update) in 1 line.
```

### Step 3: Return to Conversation Immediately

Immediately after launching the sub-agent, inform the user as below and **continue the discussion right away**:

```
Saving in background. You can continue the discussion.
You will be notified when complete.
```

When the sub-agent completion notification arrives, report the saved file path in 1 line.
