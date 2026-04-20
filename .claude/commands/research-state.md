# /research-state — Update research/state.md (with optional README sync & standalone export)

Updates the project's research state snapshot — a single-file "where we are right now" document designed for fast re-entry and external LLM sharing.

`state.md` sits between two other views:
- `/discuss` cache (~full index, 100K+ tokens, internal use)
- `README.md` (human-readable summary, history-oriented)

`state.md` is optimized for a different use case: a compact (~3–5K tokens) always-current "single active thread + decision tree" snapshot you can paste into ChatGPT/Gemini or skim after a break.

Two modes:
- **default** — refresh `research/state.md` (AUTO sections auto, MANUAL sections via Claude proposal + user approval). Optionally sync stale README sections.
- **--export** — generate `research/state_standalone.md` by inlining pointer files (for external LLM sharing).

## Usage

```
/research-state               # refresh state.md + propose MANUAL updates + optional README sync
/research-state --export      # generate state_standalone.md (gitignored by convention)
/research-state --max-lines 600   # --export with larger per-file inline cap (default 400)
<!-- PROJECT_INLINE_START -->
/research-state lang=en       # propose edits in a specific language
<!-- PROJECT_INLINE_END -->
```

| argument | description | default |
|----------|-------------|---------|
| `--export` | generate standalone bundle instead of updating state.md | off |
| `--max-lines N` | per-file inline cap for `--export` | 400 |
<!-- PROJECT_INLINE_START -->
| `lang` | output language for proposal text. The project's CLAUDE.md defines the default | project default |
<!-- PROJECT_INLINE_END -->

## Procedure

### Step 1: Branch on mode

If user passed `--export`:
- Run `python3 research/chat/build_context.py --expand [--max-lines N]`
- Report output path + size + token estimate in 2~3 lines
- Suggest copying/attaching the standalone file when sharing externally
- **Stop here** (no MANUAL section proposals, no README sync)

Otherwise continue to Step 2.

### Step 2: Refresh AUTO sections

Run `python3 research/chat/build_context.py --state-only`.

This updates in-place:
- `<!-- AUTO:header -->` — current timestamp
- `<!-- AUTO:drift_warning -->` — mtime-based file ordering + README staleness warning
- `<!-- AUTO:pointers -->` — filtered list of existing canonical files

Report 1 line describing the AUTO refresh result.

### Step 3: Gather context for MANUAL section proposals

Read these sources to decide what MANUAL sections need updating:

1. `research/state.md` — current version (post Step 2)
<!-- PROJECT_INLINE_START -->
2. Most recent 2~3 daily logs under `research/logs/YYYY-MM-DD/log.md` (format varies by project — follow the project's research-log skill or CLAUDE.md conventions)
3. Architecture / experiment changelog files under `research/topics/<topic>/`
4. `git log --oneline -20` in `research/` to see recent commits
5. New discussion files under `research/topics/*/discussion/` with mtime after the previous `AUTO:header` timestamp
<!-- PROJECT_INLINE_END -->

Skip any file that doesn't exist. Do not read the full `/discuss` cache (`research/chat/.context_cache/context_summary.md`) — redundant with the above.

### Step 4: Propose MANUAL section updates (per section, independent Edit calls)

For each MANUAL section, decide based on the gathered context whether an update is warranted. Typical update triggers:

| Section | Update when |
|---------|-------------|
| `MANUAL:identity` | Rarely — only on paradigm shifts (e.g., new module, scope change) |
| `MANUAL:active_focus` | Current experiment changed, hypothesis evolved, or a decision-tree branch was resolved |
| `MANUAL:metrics` | New best metric achieved in any module OR checkpoint path moved |
| `MANUAL:recent_decisions` | Daily logs in the last 14 days contain decisions not yet in this list. Keep newest-first, cap at ~10~12 items |
| `MANUAL:rejected_paths` | An experiment ended in rejection with a durable lesson (to avoid re-exploration) |
| `MANUAL:open_questions` | A question was resolved (remove) or a new blocker emerged (add). Cap at ~5 |

**For each proposed section update**:
- Show a **single Edit tool call** replacing only the content between that section's markers
- Keep the `<!-- MANUAL:name -->` and `<!-- /MANUAL:name -->` markers intact
- Preserve prose style — do not restructure unless clearly needed
- If no update needed for a section, skip it silently

**If uncertain about a proposed change**: ask before the Edit.

### Step 5: README sync proposal (optional)

After state.md MANUAL edits, check `research/README.md`:

<!-- PROJECT_INLINE_START -->
Project-specific README sections commonly drift. Typical targets:

| README section | Sync check |
|----------------|------------|
| Current status / module table | Should mirror state.md `MANUAL:metrics` |
| Recent progress | Should include newest items from state.md `MANUAL:recent_decisions` with 2~3 expanded bullets each |
| Confirmed decisions history | Should be a superset of state.md `MANUAL:recent_decisions` (possibly older too — do not shorten) |
| TODO / open questions | Granular per-module TODOs; state.md captures top research-critical subset only |

The specific section names and structure depend on your project's README template.
<!-- PROJECT_INLINE_END -->

If any section is stale:
- Propose individual Edit calls (do not rewrite README wholesale)
- Show diff + seek approval per edit

If README is already in sync: report "README sync not needed" in 1 line.

### Step 6: Completion report

Report in 2~4 lines:
- Which state.md MANUAL sections were updated (or "no manual updates needed")
- Which README sections were synced (or "already in sync")
- If the project has a `research/` auto-sync hook, it handles commits. If not, suggest manual commit.

Do **not** run any `git commit`/`git push` directly.

## Design notes

- **AUTO vs MANUAL markers**: AUTO content is fully regenerated by the build script on every run. MANUAL content is only changed via explicit Edit proposals in this command — so user edits to MANUAL sections outside this command are preserved on future runs.
- **Why propose + approve, not full rewrite**: keeps user in control, prevents accidental loss of nuance in prose.
- **Why --export is separate mode**: standalone bundle is ~30~50K tokens (vs state.md ~3~5K), typically gitignored, and regenerated on demand. No point maintaining one continuously.
- **Why state.md is worth having alongside README.md**: README is history-oriented ("what happened, recently"); state.md is action-oriented ("what I'm doing right now, and what decides what comes next"). Different audiences, different update cadences.
