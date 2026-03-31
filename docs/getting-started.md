**English** | [한국어](getting-started.ko.md)

# Getting Started

> Referenced from [README.md](../README.md)

---

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI
- `conda` (for environment activation)
- `jq` (for shell JSON parsing)
- `flock` (for hook sync lock, available on Linux; on macOS install via `brew install util-linux`)
- Optional: `wandb` (metric logging — falls back to stdout parsing if unavailable)

---

## Step 1. Copy to your project

```bash
cp -r /path/to/claude-sisyphus-grad/.claude /your/project/
cp -r /path/to/claude-sisyphus-grad/scripts /your/project/
cp /path/to/claude-sisyphus-grad/CLAUDE.md /your/project/   # then edit it
cp -r /path/to/claude-sisyphus-grad/research-template /your/project/research
```

Or clone and symlink `.claude/` into your project.

---

## Step 2. Set up `research/` as a separate git repo (optional but recommended)

The pipeline includes a PostToolUse hook that automatically commits and pushes `research/` to GitHub every time Claude writes to it. This requires `research/` to be its own repository:

```bash
cd your-project/research
git init && git remote add origin https://github.com/your-user/your-research-repo.git
git push -u origin main
```

Or clone an existing repo directly into `research/`. If you skip this, auto-sync is silently disabled and logs are committed to your main repo normally.

> [Auto-sync details and hook registration](research-notes.md#github-auto-sync)

---

## Step 3. Configure CLAUDE.md

Edit `CLAUDE.md` in your project root:

```
CONDA_ENV=your_env_name
```

Optionally configure metric fetching, sync commands, etc. (see `CLAUDE.md` for details).

---

## Step 4. Run

```
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

---

## Step 5. Customize for your project

These are the pieces you need to adapt before the pipeline knows about your research.

### Discussion topic modules — Required

**File**: `.claude/commands/save-discussion.md`

The `/save-discussion` command routes saved discussions to the right directory based on keyword matching. Replace the placeholder modules with your actual research topics:

```markdown
| Module key  | Keywords                                | discussion path                               | topic log path                         |
|-------------|-----------------------------------------|-----------------------------------------------|----------------------------------------|
| `module_a`  | keyword1, keyword2, keyword3            | `research/topics/module_a/discussion/`        | `research/topics/module_a/log.md`      |
| `module_b`  | keyword4, keyword5, keyword6            | `research/topics/module_b/discussion/`        | `research/topics/module_b/log.md`      |
| `module_c`  | keyword7, keyword8                      | `research/topics/module_c/discussion/`        | `research/topics/module_c/log.md`      |
| `meta`      | research system, logging, workflow, Claude Code | `research/topics/analysis/discussion/` | (none)                                 |
```

The `meta` row handles workflow/tooling discussions — keep it as-is. Everything else reflects your project's module structure.

### Research notes templates — Required

After copying `research-template/` to `research/`, edit two files:

**`research/README.md`** — Replace the placeholder topic table with your actual research status:
```markdown
## Current Research Status

| Topic    | Status | Recent Progress       |
|----------|--------|-----------------------|
| module_a | Active | ...                   |
| module_b | On hold | ...                  |
```

**`research/CLAUDE.md`** — The operating rules for Claude's research notes behavior. Update the module references (e.g., `topics/<topic>/`) to match your actual topic directory names — these should correspond to the module keys in the `save-discussion` table above.

### Permission mode — Recommended for autonomous runs

**File**: `.claude/settings.local.json`

For the `/train` orchestrator to run without manual approval at each step:
```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```

> See [Caution note in customization guide](customization.md#permission-mode) before enabling this.

### Reviewer roles — Optional

**File**: `.claude/prompts/train-review-pipeline.md`

Adapt the 7-reviewer panel to your domain. See [customization guide](customization.md#reviewer-roles).

### Abort / convergence conditions — Optional

**Files**: `.claude/prompts/train-monitor.md`, `.claude/prompts/train-orchestrator-decisions.md`

Tune for your metric noise level. See [customization guide](customization.md#abort-conditions).

---

## File structure

```
.claude/
  commands/
    train.md              # /train launcher
    review.md             # /review standalone
    analyze.md            # /analyze pre-analysis
    discuss.md            # /discuss research context loader
    save-discussion.md    # /save-discussion  ← customize module table here
  prompts/
    train-orchestrator.md          # main orchestrator logic
    train-orchestrator-decisions.md # Strict Convergence + Bold Improvement principles
    train-monitor.md               # metric polling + epoch-level review
    train-review-pipeline.md       # multi-agent review (A~G + Judge)  ← customize reviewers here
    train-recording-rules.md       # logging format + secretary rules
    train-code-modifier.md         # autonomous code modification procedure
    discuss-system.md              # discuss mode behavior rules
  hooks/
    sync-research-log.sh   # PostToolUse hook: auto-sync research/ on file write
  skills/
    research-log/SKILL.md  # log templates + directory structure
    weekly-summary/SKILL.md # weekly summary generation rules
  settings.local.json      # permission allowlist + hook registration  ← set defaultMode here
scripts/
  train-loop.sh            # external loop wrapper (spawns claude -p per iteration)
research-template/
  CLAUDE.md                # template: copy to research/CLAUDE.md  ← customize topic names here
  README.md                # template: copy to research/README.md  ← update research status here
docs/
  getting-started.md       # this file
  customization.md         # customization guide
  multi-agent-review.md    # multi-agent review pipeline detail
  train-internals.md       # /train loop mechanics + state file + experiment files
  research-notes.md        # research directory structure + file roles
  research-log-rules.md    # log writing philosophy and section-by-section rules
```
