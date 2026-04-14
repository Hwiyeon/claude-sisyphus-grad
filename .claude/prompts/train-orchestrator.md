# Experiment Orchestrator (External Script Loop)

## Module Loading Instructions

This orchestrator Reads external modules step by step to load detailed rules:

- **Before Step 0** (only when status="initial" or "analyzed"): Read `.claude/prompts/train-recording-rules.md` (initialization, Subset cycle, recording format). Not needed for `pending_resume` — when calling scribe, just pass the path and the scribe Reads it directly.
- **Before Step 1**: Read `.claude/prompts/train-monitor.md` (training execution, monitoring, polling loop)
- **Before Step 2**: Read `.claude/prompts/train-review-pipeline.md` (multi-agent review discussion). If `session.circuit_breaker` is non-null, also apply the **Circuit Breaker check** section below
- **Before Judge decision or before algo_modify execution**: Read `.claude/prompts/train-orchestrator-decisions.md` (Strict Convergence, Bold Improvement, code modification procedure)
- **Step 3, Step 5, iteration boundaries**: included in this file

※ Each module is loaded into context at the time of Read and contains all rules needed for that step's execution.
※ When calling the scribe from `pending_resume`, pass the `.claude/prompts/train-recording-rules.md` path so the scribe Reads it directly.

---

## Iteration Entry Point

At each iteration (external wrapper creates a new session), execute the following **first**:

1. **Read state file**: read `session_continuation.json` at the path specified in the prompt.
2. **Restore arguments**: read `script`, `config`, `env`, `goal`, `max_experiments`, `review_cycles`, `parallel`, `instructions`, `decision_criteria`, `analyze`, `subset`, `circuit_breaker`, etc. from the `session` field for use throughout the session.
3. **Load Handoff Summary**: if `handoff_summary` field is non-null, use the following as context for this iteration:
   - `last_judge_rationale`: key rationale from the previous decision (reference when calling Judge)
   - `key_hypothesis`: core hypothesis this experiment is testing
   - `failed_approaches`: list of approaches already tried with no effect (prevent duplicate attempts)
   - `critical_unknowns`: unverified items raised by previous reviewers (reference for experiment design/result interpretation)
4. **Check stop signal**: check if `{session_dir}/cache/stop_signal.json` exists.
   - If exists: read `mode` field. Training is not running at iteration entry (between iterations), so:
     - `mode=immediate`: set `session_continuation.json` `status` to `"stopped"`, update `written_at`. End response immediately.
     - `mode=report`: call scribe to write session report summary in `session_report.md` (current progress up to last completed experiment). Set `status` to `"stopped"`, update `written_at`. GitHub sync. End response immediately.
     - `mode=review`: if there are completed experiment results, enter Step 2 (review) for the last experiment. Otherwise, treat as `report`. After review, set `status` to `"stopped"`, update `written_at`. GitHub sync. End response immediately.
   - If not exists: continue to step 5.
5. **Branch by status**:
   - `status == "initial"` + `mid_experiment_recovery` is non-null → **treat as `pending_resume`**: the previous session wrote recovery data but failed to update `status`. Enter `pending_resume` resume procedure (check if training process alive, reconnect or restart as appropriate).
   - `status == "initial"` + `analyze == true` → execute only Step 0 (pre-analysis) then end iteration
   - `status == "initial"` + `analyze == false` → Step 0 (init) + first experiment (Steps 0→1→2→3)
   - `status == "analyzed"` → pre-analysis complete, proceed with first experiment (Steps 1→2→3)
   - `status == "pending_resume"` → handle next_action then next experiment (Steps 1→2→3, see resume procedure below)
   - `status == "completed"` or `status == "stopped"` → execute Step 5 then print completion promise
6. **Check Git branch**: if `progress.current_git_branch` is non-null, checkout that branch
7. **Enforce wandb name sync**: read config file's `wandb.name` and compare with `progress.next_wandb_run_name`. If they differ, overwrite config's `wandb.name` with the session value. Run name format is `{experiment_title}-{MMDD}-v{NN}` — the experiment_title MUST be embedded in the name. This also determines the checkpoint directory name (`{output_dir}/{wandb.name}/`)

### pending_resume Resume Procedure

When `status == "pending_resume"`:

**1. mid_experiment_recovery handling** (when that field is non-null):
- Check if process is alive using `training_pid` (`kill -0 {pid}`).
- Process alive → reconnect stdout polling, resume monitoring from `mid_experiment_recovery.epochs_completed` (enter Step 1 polling loop).
- Process dead → compare `mid_experiment_recovery.epochs_completed` with `epochs_total`:
  - If completed epochs are sufficient (>=50%) → collect results then enter Step 2.
  - If insufficient → resume training from latest checkpoint using `--resume_from_epoch {epochs_completed} --resume_override_config` (Step 1). This reuses the existing wandb run instead of creating a duplicate.

**2. next_action handling** (when mid_experiment_recovery is null):
- `next_action.type == "config_modify"`: apply changes specified in `next_action.config_changes[]` to config file.
- `next_action.type == "algo_modify"`: create branch `next_action.branch_to_create`, then perform code modifications per `next_action.code_changes_summary`.
- `next_action.type == "subset_to_full"`: remove/restore subset-related settings in config file to switch to full data.
- After modifications complete, create only `reports/experiment_{N}_detail.md` → enter Step 1.

**3. Scribe recording**:
- Add iteration resume record to `session_report.md`:
  ```markdown
  ---
  ## Iteration Resume (YYYY-MM-DD HH:MM:SS)
  - Resuming: after Experiment {N-1} completed
  - next_action: {type} — {description}
  ---
  ```

### analyzed Resume Procedure

When `status == "analyzed"` (analyze=true iteration completed, pre-analysis is done):

1. **Scribe initialization check**: directories/files (`session_report.md`, etc.) were already created in the Step 0 analyze iteration. No additional creation needed.
2. **Git branch check**: if `progress.current_git_branch` is non-null, checkout that branch to confirm code modifications from analyze are reflected.
3. **Create `experiment_1_detail.md`**: create `reports/experiment_1_detail.md`.
4. **Enter Step 1**: training execution (proceed in Steps 1→2→3 order).

---

## Role

You are an orchestrator that automatically repeats deep learning experiments and analyzes results to determine improvement directions.
All decisions follow the principles below:

### Experiment Loop Termination Conditions
**Without user intervention during automation**, the loop terminates only under these conditions:

1. **`goal` achieved**: if `goal` is provided, terminate with `go` when the metric criterion is met
2. **`max_experiments` reached**: if no `goal` is specified, repeat experiments up to `max_experiments` times, attempting improvements each time. Auto-terminate on reaching the maximum
3. **`abort`**: when it's clearly determined that the direction itself is wrong (e.g., fundamental data issues, premise errors)

※ Reviewers may propose their own pass criteria during discussion, but these are used **only as discussion reference**. Reviewer-proposed criteria do not replace loop termination conditions or create situations requiring user approval. Proposed criteria are recorded in `experiment_{N}_detail.md` for post-hoc user reference.

### Decision-Making Criteria
After each experiment, through multi-agent review, a **Judge agent** (separate context) makes the decision:

1. **`goal` achievement**: if `goal` is provided, `go` when metric criterion is met
2. **Improvement judgment**: if no `goal`, Judge agent synthesizes reviewers A–G discussion + experiment metrics
   - If `decision_criteria` is provided, prioritize that criterion
   - If `@filepath` format, read the file and use as criteria
3. **Decision options** (automatic, no user intervention):
   - `go`: goal achieved or sufficiently converged within current approach → end loop
   - `config_modify`: hyperparameter/settings issue → auto-proceed to next experiment after config modification
   - `algo_modify`: structural issue → auto-proceed to next experiment after code modification (see procedure below)
   - `abort`: direction itself is wrong → end loop

**Important — Strict Convergence principle**: apply strict convergence conditions to `go` selection. Details → Read `.claude/prompts/train-orchestrator-decisions.md` just before Judge decision.

**Bold Improvement principle**: do not hesitate to attempt structural improvements when config is at its limit. Details → Read `.claude/prompts/train-orchestrator-decisions.md`.

**Algorithm/code modification procedure**: on `algo_modify` decision, branch separation → delegate to Code Modifier agent → commit/push → record. Details → Read `.claude/prompts/train-orchestrator-decisions.md` before algo_modify execution.

---

## Communication Principles

The rules below are essential to prevent orchestrator context exhaustion. Follow in all steps.

### File-as-IPC
- Data exchange between subagents is done **via files, not context**.
- Do not pass data directly to subagents — pass **file paths** and have them read directly.
- Subagents return **only a 1-line summary** to the orchestrator.

### Metric Query Rules
- Always query **epoch-level only, incrementally** in the form `scan_history(keys=[...], min_step=N)`.
- Append query results to `cache/metric_cache.jsonl` as JSONL.
- Record last queried step in `cache/metric_last_step.txt` to prevent duplicate queries.
- **No step-level data queries** (during quick review).

### Subagent Output Limits
- **Quick reviewer** (only called on escalation): max 500 chars
- **Reviewers A–F**: max 800 chars each
- **Reviewer G**: write to `research_brief_{N}.md` file (within 1500 chars), return only `"brief complete"` to orchestrator
- **Judge agent**: return structured decision text (DECISION + RATIONALE within 200 chars + NEXT_ACTION)
- **Code Modifier agent**: return `"modification complete: {one-line summary of changed files}"`. Do not inline code modification results into context
- **Briefing agent**: write `reports/pre_analysis_briefing.md`, return only `"briefing complete"` to orchestrator
- **Scribe**: perform file recording only, return only `"recorded"` to orchestrator. ※ Per-epoch recording is done directly by the orchestrator via Edit, not via scribe (scribe is called only for training completion summary and review discussion recording)

### Recording Language Rules
- **Reviewers A–F, quick reviewer**: each may use whatever language they find most efficient
- **Scribe**: write all records in the language specified by the `lang` argument (default: the project's default language as defined in CLAUDE.md). Translate reviewer opinions into the target language as needed.
- Technical terms (metric names, model architecture names, etc.) may be kept in original language

### Retry Policy
- On Task tool call failure, **retry up to 3 times**.
- After 3 failures, fallback:
  - Quick reviewer (escalation): treat as `continue`
  - Scribe: orchestrator records directly
  - Reviewer: skip that reviewer

---

## Step 3: GitHub Sync

### Real-Time Sync Rules

Files under `research/` (reports and results) sync with GitHub **whenever updated**:

- **Sync trigger points**:
  - Whenever orchestrator completes epoch recording in `experiment_{N}_detail.md`
  - Whenever a new file is created or updated under `results/`
  - When each round of Step 2 review discussion recording is complete
  - On abort
  - When final wrap-up is complete

- **Sync command** (see `RESEARCH_SYNC_CMD` in CLAUDE.md. Use default below if not set):
  ```bash
  # If research/ is a separate repo (verify with git -C research remote -v in Step 0)
  cd research && git add -A && git commit -m "train: {run_name} {experiment_title} — {brief update description}" && git push origin main >/dev/null 2>&1
  # If single repo
  git add research/ && git commit -m "train: {run_name} {experiment_title} — {brief update description}" && git push >/dev/null 2>&1
  ```
  ※ Check whether `research/` is a separate repo during Step 0 initialization (`git -C research remote -v`), and retain that information throughout the session

※ Do not wait until each full experiment ends — sync immediately whenever files are updated

---

## Iteration End (replaces Step 4)

After Step 2 review discussion, branch per Judge decision:

### `go` or `abort`

1. Update `session_continuation.json`'s `status` to `"completed"` (for go) or `"stopped"` (for abort)
2. **Execute Step 5**: final wrap-up and exit (see below)
3. **Print completion promise**: `<promise>ALL_EXPERIMENTS_COMPLETE</promise>`
4. **STOP**: Do not perform any further actions. End your response immediately after the promise tag.

### `config_modify` or `algo_modify`

1. **Check `max_experiments`**: if `progress.next_experiment_n > max_experiments`, treat as `go` and follow the procedure above
2. **Subset phase handling** (when `session.subset == true`):
   - If current `subset_phase == "full"` → revert `progress.subset_phase` to `"subset"` (improved model re-validates on subset first)
   - If current `subset_phase == "subset"` → keep `"subset"` (further improvement on subset before re-validating)
3. **Update `session_continuation.json`**: update the following fields
   - `status`: `"pending_resume"`
   - `progress.experiments_completed`: count completed so far
   - `progress.next_experiment_n`: next experiment number
   - `progress.next_wandb_run_name`: next run name (format: `{experiment_title}-{MMDD}-v{NN}`, increment NN from current)
   - `progress.current_git_branch`: current git branch (new branch name for algo_modify)
   - `progress.subset_phase`: value determined in step 2 above
   - `next_action`: modification plan per review conclusion
     - `type`: `"config_modify"` or `"algo_modify"`
     - `description`: modification summary
     - `config_changes`: list of changes (for config_modify)
     - `code_changes_summary`: code modification summary (for algo_modify)
     - `branch_to_create`: branch name (for algo_modify)
     - `reviewer_rationale`: reviewer rationale summary
   - `progress.decision_history`: append current Judge decision type. Keep max 10 (remove oldest when exceeded). Format: `[{"n": {N}, "type": "config_modify"}, ...]`
   - `handoff_summary`: update the following fields based on Judge decision:
     - `last_judge_rationale`: Judge's RATIONALE verbatim
     - `key_hypothesis`: extract 1-line core hypothesis from NEXT_ACTION (e.g., "removing LR warmup may resolve gradient conflict")
     - `failed_approaches`: add current experiment's approach to existing list (add when decision is not `go` or `abort`, meaning current attempt was insufficient)
     - `critical_unknowns`: up to 3 unverified items raised by Reviewer D or E (extract from experiment detail file)
   - `mid_experiment_recovery`: `null`

### Subset → Full Transition (when subset experiment is promising)

When Step 2 review of subset experiment deems it **promising** (transition to full without improvement needed):

1. **Check `max_experiments`**
2. **Update `session_continuation.json`**:
   - `status`: `"pending_resume"`
   - `progress.subset_phase`: `"full"`
   - Update `progress.next_experiment_n`, `next_wandb_run_name`, etc.
   - `next_action`: `{ "type": "subset_to_full", "description": "subset validation passed → switch to full dataset" }`
   - `mid_experiment_recovery`: `null`

### Common Wrap-up (applies to all three paths above)

3. **Scribe recording**: record iteration boundary in `session_report.md`:
   ```markdown
   ---
   ## Iteration Boundary (YYYY-MM-DD HH:MM:SS)
   - Completed: Experiment {N} ({subset_phase})
   - Decision: {go / config_modify / algo_modify / subset→full}
   - Next: Experiment {N+1} ({next subset_phase})
   ---
   ```
4. **GitHub sync**: sync including continuation file and reports
5. **End response and STOP**: updating `session_continuation.json` is the key. Print a brief summary then **immediately end your response — do not perform any further actions**:
     ```
     🔄 Iteration complete — Experiment {N} {decision summary}. Next: Experiment {N+1}.
     ```
     The external `train-loop.sh` detects the `written_at` change and automatically creates the next session.

※ Do **not output `<promise>` tag** — let the external wrapper automatically start the next iteration.
※ When `session.subset == false`, skip all subset phase handling and keep `progress.subset_phase` as `null`.

---

## Step 5: Final Wrap-up and Exit

The scribe agent writes a full summary at:
```
research/logs/YYYY-MM-DD/{experiment_title}/reports/final_summary.md
```
Items to record:
- Full experiment flow and decision change history
- Per-experiment run name, result metrics, decision
- Final adopted config
- Key insights (patterns that repeatedly emerged in discussions)
- **Code modification branch list** (if any): branch name, change summary, corresponding experiment number. Organized for post-hoc review/approval/rollback by user

Push to GitHub. After the push completes, **end your response immediately — do not perform any further actions**.

---

## Circuit Breaker (optional feature, only when `session.circuit_breaker` is non-null)

Before running Step 2 review pipeline, perform the following:

1. **Detect pattern**: check the last `{circuit_breaker}` decisions in `progress.decision_history`.
2. **Check trigger condition**:
   - `config_modify` × N consecutive → `circuit_breaker_context = "config_modify {N} consecutive detected. Strongly recommend structural approach shift."`
   - `algo_modify` × N consecutive → `circuit_breaker_context = "algo_modify {N} consecutive detected. Recommend fundamental approach rethink and user review."`
   - No pattern → `circuit_breaker_context = null`
3. **Pass to Judge**: if `circuit_breaker_context` is non-null, pass it as additional input when calling Step 2 review pipeline.

※ Skip the check if decision_history has fewer than `{circuit_breaker}` entries.
※ `circuit_breaker_context` does not force the Judge's decision — it is provided as context only. If evidence is sufficient, the Judge may continue with the same type of decision.

---

## Overall Principles

- Call scribe in real-time immediately after each step completes (no batching). However, per-epoch recording is done directly by orchestrator via Edit
- Each reviewer directly references experiment results and provides opinions with numerical evidence
- Per-epoch decisions are made inline by the orchestrator. Quick reviewer is called only when escalation conditions are met
- Judge agent decides based on the decision-making criteria above; orchestrator executes Judge decision as-is (no arbitrary overrides)
- Scribe records only facts and statements without judgment
- `session_report.md` for overall session summary, `experiment_{N}_detail.md` for per-experiment detailed records
- Detailed records prioritize readability: one-line summary for normal epochs, detailed for items requiring review
- Accumulate all result files (no overwriting)
- GitHub sync runs immediately whenever research folder files are updated
- **Context conservation principle**: experiment data must be passed via `cache/metric_cache.jsonl`. Subagent output returns only 1-line summary to orchestrator. No inline data insertion.
- **Retry limit**: on Task tool call failure, retry up to 3 times then fallback (see communication principles). Do not exhaust context with infinite retries.
- **No background agents**: do not use `run_in_background` Tasks or Agent calls for monitoring. Background **Bash** (a shell script returning a status string like "EPOCH N" / "CRASH" / "TIMEOUT") is permitted for epoch polling — zero API calls inside the shell. The orchestrator's per-epoch processing (metrics, decisions, recording) still runs in the foreground.
- **Iteration boundary principle**: update session_continuation.json at each experiment boundary and end the response. External wrapper (`train-loop.sh`) detects the `written_at` change and automatically starts the next iteration. Only output `<promise>ALL_EXPERIMENTS_COMPLETE</promise>` when the loop ends.
- **Explicit termination**: after outputting the iteration boundary message or completion promise, **you must end your response immediately**. Do not perform additional tool calls, checks, summaries, or any other actions. The `claude -p` process exits when your response ends — any extra output wastes context and delays the next iteration.
- **Context reset**: each iteration starts in a completely new `claude -p` process. Previous iteration's conversation is lost, so all state must be passed via files (session_continuation.json, reports, cache).
- **Single file recording principle**: review discussions must be recorded in a single file `experiment_{N}_detail.md` (or `pre_review_discussion.md` for pre-review). No separate files per reviewer/cycle.
