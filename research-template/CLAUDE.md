# Research Notes Operating Rules

- Log writing templates, directory structure, README updates, sync → see `research-log` skill
- Weekly summary → see `weekly-summary` skill

## 1. Daily Log Operations

### Role
- **Index + non-topic detailed records**
- Topic-related work: 1-2 line summary + `→ topics/<topic>/log.md` link
- Non-topic work (infrastructure, systems, etc.): detailed records as usual

### When to Create
- Create `logs/YYYY-MM-DD/log.md` immediately when the day's discussion starts
- Update the log when requested by the user
- `git commit & push` immediately on each update

### Writing Principles (non-topic work)
- No conclusion-only summaries — richly describe the details of trial-and-error
- Always include ASCII Art diagrams when model structure changes
- Copy visualization images to the log folder and reference them
- Keep to one file per day (`log.md`)

## 2. Module-Specific Topic Logs (Primary Detailed Records)

- `topics/<topic>/log.md` is the **primary** detailed record for that topic
- Record in detail: ASCII Art diagrams, trial-and-error, visualization images
- Each entry separated by date header (`## YYYY-MM-DD`) in chronological order
- Daily log contains only 1-2 line summary + topic log link

## 3. Architecture Reference & Experiment Log

### Architecture Reference (`architecture_<module>.md`)
- **Current best specification** — the document that instantly answers "what's the current version?"
- Only update when user requests it (not auto-updated)
- Does not reflect failed experiments — records best version only
- Must include weight file path
- On update, overwrite the entire file with current best (previous versions tracked via git history only, no in-file changelog)

### Experiment Log (`experiment_log.md`)
- **Architecture changelog** — history of changes to architecture files (newest first)
- 3-level hierarchy:
  - `##` = architecture version (structural changes — model structure, new components)
  - `###` = algorithm changes (loss replacement, prediction approach, training strategy)
  - `####` = config tuning (LR, batch size, loss weight, schedule, etc.)
- Record both successes and failures

## 4. Related Work

- Papers and techniques mentioned during discussion are organized by topic in `related_work/`
- Added naturally during discussion flow (when user requests or at end of discussion)
