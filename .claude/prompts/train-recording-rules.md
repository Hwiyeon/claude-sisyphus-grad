# Experiment Recording Rules + Step 0 Initialization + Subset Cycle

> This module is loaded from `train-orchestrator.md`. Read before executing Step 0 when status="initial" or "analyzed".
> When status is `pending_resume`, the orchestrator does not Read this — pass this file path (`.claude/prompts/train-recording-rules.md`) when calling the scribe so the scribe Reads it directly.

## Interface Contract

Values provided by the orchestrator:
- `session`: entire session field from session_continuation.json
- `session_dir`: `research/logs/{YYYY-MM-DD}/{experiment_title}`
- `experiment_n`: current experiment number
- `config`, `script`, `env`, `goal`, `max_experiments`, `review_cycles`, `parallel`
- `instructions`, `analyze`, `subset`, `decision_criteria`

---

## Step 0: Initialization (only when status="initial")

### Pre-Instructions Processing (`instructions`)

When `session.instructions` is non-null, perform the following before training:

1. **Load reference materials**: if `@filepath` format is included, read the file to understand the content
2. **Analyze instructions**: understand user requirements and formulate an execution plan
   - Config modification request → read `{config}` file and apply the specified changes
   - Code modification request → read related source code and apply modifications
   - Analysis/review request → analyze reference materials and reflect in judgment
3. **Output modification summary**: show changes to user and get confirmation before proceeding
4. **Scribe recording**: record applied pre-instructions and change details in `session_report.md`

### Pre-Analysis and Model Improvement (`analyze` mode, when `session.analyze == true`)

When `analyze` flag is active, comprehensively analyze the current model state before training and derive/apply improvements.

**1. Status collection (Briefing agent)**:
Call Briefing agent via Task tool to delegate status collection. Orchestrator does not directly explore/read files.
- **Input** (paths only):
  - `eval_results/` (latest best model performance)
  - `research/logs/` (latest training reports, research logs)
  - `research/README.md` (research direction/context)
  - `{script}` and related model definition files (current architecture)
- **Instruction**: explore the paths above and write the following to `reports/pre_analysis_briefing.md`
  - Latest best model performance metrics (from eval_results or previous experiment results)
  - Recent training trends, bottlenecks, reviewer opinion summary (from reports)
  - Current research direction and context (from research logs)
  - Current model architecture summary (from code)
- **Returns**: only `"briefing complete"` to orchestrator

**2. Multi-agent analysis discussion**:
Based on `reports/pre_analysis_briefing.md` written by the Briefing agent, run a multi-agent discussion recording to `pre_review_discussion.md`. Discussion topics:
- What is the performance bottleneck in the current model (numerical evidence required)
- Can it be resolved with config-level adjustments, or does it need structural changes
- Specifically what improvements to attempt (architecture changes, loss function replacement, data pipeline improvements, etc.)
- Risk and expected impact assessment

Reviewer composition and discussion format are the same as Step 2 multi-agent review discussion (G Research Brief → round 2 → round 3 → Judge decision, repeated `review_cycles` times).

**3. Apply improvements (Code Modifier agent)**:
Apply improvements **automatically without user confirmation** per discussion conclusions:
- **Execute common procedure**: Read `.claude/prompts/train-code-modifier.md` and follow the common procedure.
  - `{input_file}`: `reports/pre_review_discussion.md`
  - `{branch_name}`: `train/{experiment_title}/pre-analyze-mod`
  - `{record_targets}`: end of `pre_review_discussion.md`
- **GitHub sync**: also sync research/ records per Step 3 rules

**4. End analyze iteration** (when `analyze == true`):
- Once Step 0 pre-analysis (instructions processing + Briefing + multi-agent discussion + Code Modifier) is complete, **end the iteration without starting training**.
- Update `session_continuation.json`'s `status` to `"analyzed"`.
- Record current branch name (e.g., `train/{experiment_title}/pre-analyze-mod`) in `progress.current_git_branch`.
- Perform GitHub sync (Step 3 rules).
- Print iteration end text and exit:
  ```
  🔄 Iteration complete — pre-analysis done. Next: Experiment 1 training start.
  ```
- → External wrapper (`train-loop.sh`) creates new session → enters Step 1 with `"analyzed"` status in clean context.

**4-alt. When `analyze == false`**: proceed directly to Step 1 (training execution) after Step 0 scribe initialization (existing behavior).

※ The `analyze` mode pre-analysis runs in a separate iteration. In subsequent experiment loops, the existing multi-agent review (Step 2) naturally continues model improvement.
※ When both `instructions` and `analyze` are provided, process `instructions` first, then run `analyze` analysis.

### Pre-Review Discussion (`pre_review_discussion.md`)

When discussing model improvements, architecture changes, etc. via multi-agent review before training (e.g., deriving v4→v5 model improvements), record all discussion content in **a single file `reports/pre_review_discussion.md`**.

- Do not name it `experiment_0_detail.md` — pre-training discussion is not an experiment and gets no experiment number
- No separate files per reviewer — all cycle/round discussion content recorded in this single file in order
- Recording format is the same as the review discussion recording format in `Experiment Detail MD` below
- Final conclusion (Judge decision) also recorded at the end of this file

### Scribe Initialization

**Call scribe agent** (Task tool):
- Create the directory structure below:
  ```
  research/logs/YYYY-MM-DD/{experiment_title}/
  ├── results/
  ├── reports/
  └── cache/
      ├── metric_cache.jsonl   (per-iteration metric JSONL)
      └── metric_last_step.txt       (last queried step)
  ```
- Create `reports/session_report.md` and write header:
  ```markdown
  # Experiment Session: {experiment_title}
  - Date: YYYY-MM-DD
  - script: {script}
  - config: {config}
  - goal: {goal}
  - max_experiments: {max_experiments}
  - review_cycles: {review_cycles}
  ```
- **Create Experiment Detail MD**: `reports/experiment_{N}_detail.md`
  - Create new for each experiment (run). `N` is the current experiment number
  - Header and overall structure: see **Experiment Detail MD Full Format** below
  - This single file accumulates training logs (per-epoch quick reviews), training summary, multi-agent review discussion in order
  - No separate files per reviewer/cycle — all content integrated in this single file
- After each step completes, the orchestrator calls the scribe for real-time recording

---

## Subset Cycle Training (applied when `session.subset == true`)

When `subset` flag is active, **subset → full as one cycle** is repeated. Each phase is a separate experiment (experiment) and transitions at iteration boundaries.

### Overall Flow

```
Exp 1 (subset) → review → promising? → Exp 2 (full) → review → improvement needed?
                    ↓ not promising                         ↓ apply improvements
              apply improvements                    Exp 3 (subset) → review → promising? → Exp 4 (full) → ...
              Exp 2 (subset, re-validate)                        ↓ not promising
                                                          apply improvements → Exp 4 (subset) → ...
```

### Subset Experiment (`progress.subset_phase == "subset"`)

- **Config modification**: just before Step 1 training, modify dataset-related settings in config file to **use only 20% of full data**
  - Set `dataset.subset_ratio: 0.2` or equivalent config item (apply appropriately per config file structure)
  - If no such config item, understand how subset processing is done in data loading code and apply
- **Run experiment**: run normal experiment loop (Step 1→2→3) with subset data
- **Step 2 review decision branches**:
  - **Promising** (metric improving trend, converging tendency, architecture validity confirmed):
    - Change `subset_phase` to `"full"`
    - Set `next_action.type` to `"subset_to_full"` (only config restoration needed)
    - End iteration → external wrapper creates new session → next experiment runs on full dataset
  - **Not promising** (diverging, plateauing, structural issues):
    - Keep `subset_phase` as `"subset"`
    - Set `next_action` to `config_modify` or `algo_modify` (same as existing procedure)
    - End iteration → external wrapper creates new session → re-validate with **subset** after improvements
  - Judgment criteria: evaluate comprehensively based on loss convergence pattern, metric trend direction, overfitting. **Trends and patterns** matter more than absolute values

### Full Dataset Experiment (`progress.subset_phase == "full"`)

- **Config restoration**: when `next_action.type == "subset_to_full"`, restore subset-related config to original (use full data)
- **Run experiment**: normal experiment loop (Step 1→2→3) on full dataset
- **Step 2 review decision branches**:
  - **`go`**: goal achieved or converged → end loop (Strict Convergence principle applies)
  - **Improvement needed** (`config_modify` or `algo_modify`):
    - **Revert `subset_phase` to `"subset"`** — improved model must first be re-validated on subset
    - Set `next_action` to modification plan (same as existing procedure)
    - End iteration → external wrapper creates new session → restart from **subset** after improvements
  - **`abort`**: end loop

### Phase Transition Recording

Record phase transition in `session_report.md`:
```markdown
---
## Phase Transition: {subset→full / full→subset} (YYYY-MM-DD HH:MM:SS)
- After Experiment {N} completed
- Transition rationale: [review conclusion summary]
- Previous phase best metric: [summary]
---
```

### `next_action.type == "subset_to_full"` Handling (when resuming from pending_resume)

When `next_action.type == "subset_to_full"` is encountered at `pending_resume`:
1. Remove/restore subset-related settings in config file to switch to full data usage
2. Create `reports/experiment_{N}_detail.md` (changes: "subset → full dataset transition")
3. Enter Step 1 (training execution)

※ Each subset/full gets a separate experiment number, both count toward `max_experiments`. Allocate efficiently within the total budget.
※ When `subset == false`, `progress.subset_phase` is always `null` and this entire procedure is ignored.

---

## session_report.md Template

```markdown
# Experiment Session: {experiment_title}
- Date: YYYY-MM-DD
- script: {script}
- config: {config}
- goal: {goal}
- max_experiments: {max_experiments}
- review_cycles: {review_cycles}

---

## Step 0 Initialization Complete (YYYY-MM-DD HH:MM:SS)
- Directories created
- Pre-instructions: {applied/not applied and summary}

---
```

On iteration resume, append:
```markdown
---
## Iteration Resume (YYYY-MM-DD HH:MM:SS)
- Resuming: after Experiment {N-1} completed
- next_action: {type} — {description}
---
```

---

## Experiment Detail MD Full Format

`reports/experiment_{N}_detail.md` is written in the format below. Both training logs and review discussions are recorded in **this single file**.

```markdown
# Experiment {N}: {run_name}
- config: {config}
- start time: HH:MM:SS
- changes: [key changes in this experiment]

---

## Training Log

#### E1/{total} ({elapsed}s)
`train_loss=... | val_loss=... | val_f1=... | val_auc=... | lr=...`
**auto decision**: `continue`

#### E2/{total} ({elapsed}s)
`train_loss=... | val_loss=... | val_f1=... | val_auc=... | lr=...`
**auto decision**: `continue`

#### E7/{total} ({elapsed}s)
`train_loss=... | val_loss=... | val_f1=... | val_auc=... | lr=...`
**quick review**: `continue` — val_loss rising consecutively but still within convergence range.

#### E8/{total} ({elapsed}s)
`train_loss=... | val_loss=... | val_f1=... | val_auc=... | lr=...`
**auto decision**: `abort` — val_loss increased >3x from epoch 1, diverging.
> abort details: [metric snapshot, rationale]

...

## Training Summary
- Total {N} epochs completed
- Best {key_metric}: E{N} = ...
- Best val_loss: E{N} = ...
- Key observations: [summary]

---
---

## Multi-Agent Review Discussion

===

### Cycle 1/{review_cycles}

---

#### Research Brief (Reviewer G)

[G's research brief summary — related research and methodology proposals]
→ full: `reports/research_brief_{N}.md`

---

#### Round 2

**Reviewer A (stats/metrics):**

[A's full opinion — including numerical evidence]

---

**Reviewer B (algorithm/structure):**

[B's full opinion]

---

**Reviewer C (data/design):**

[C's full opinion]

---

**Reviewer D (Feasibility Assessor):**

[D's feasibility assessment — including [LOW/MEDIUM/HIGH] risk per proposal]

---

**Reviewer E (Supplement):**

[E's supplemental opinion]

---

**Reviewer F (Moderator):**

[F's consensus/conflict summary]

---

#### Round 3 (Opinion Update)

**Reviewer A:** [maintain/revise] — [reason]

**Reviewer B:** [maintain/revise] — [reason]

**Reviewer C:** [maintain/revise] — [reason]

===

### Cycle 2/{review_cycles}

(same format as above — `---` between reviewers, `===` between cycles)

...

===

### Judge Decision
- **Decision**: [go / config_modify / algo_modify / abort]
- **Rationale**: [detailed rationale]
- **Next experiment plan**: [if applicable]
```

### Visibility Rules Summary

- **Epoch decisions**: separated per epoch with `#### E{N}/{total}` header. Metrics in code block, decision (`auto decision` or `quick review`) in **bold**.
- **Between reviewers**: insert `---` (horizontal rule) between each reviewer's opinion.
- **Between cycles**: insert `===` between cycles for clear visual separation.
- **No separate files**: all content accumulates in this single file in order.
