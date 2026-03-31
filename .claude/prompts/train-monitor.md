# Step 1: Training Execution + Monitoring

> This module is loaded from `train-orchestrator.md`. Read before executing Step 1.

## Interface Contract

**Input** (provided by orchestrator):
- `script`: path to training script
- `config`: path to config file
- `env`: conda environment name
- `experiment_n`: current experiment number
- `run_name`: identifier name for this run
- `session_dir`: `research/logs/{YYYY-MM-DD}/{experiment_title}`
- `parallel`: number of parallel training models

**Returns**: "training complete" or "training aborted" (passed to Step 2)

---

## Training Execution

- run_name is generated in `YYYYMMDD-v{experiment_number 2-digit}` format (e.g., `20240315-v01`)
  - Use `progress.next_run_name` if present
- Write run_name directly into the logging name field in config file, then run training (when using wandb etc.):
  ```bash
  conda activate {env} && python {script} --config {config}
  ```
  ※ If no logging tool is used, specify run_name in stdout output header etc.
- Training script is run in **background** (`run_in_background`), orchestrator polls stdout directly

### Parallel Training (`parallel` >= 2)

When `parallel` is 2 or more, train **multiple models simultaneously** based on the same config:
- Each model runs as a separate background process
- Add sub-index to run_name: `YYYYMMDD-v{experiment_num}-m{model_num}` (e.g., `20240315-v01-m1`, `20240315-v01-m2`)
- Poll each process's stdout individually
- After all models complete, collect results and save each to `results/experiment_{N}_m{M}.json`
- In Step 2 review, compare and analyze all model results together

---

## Monitoring During Training: Orchestrator Inline Polling Loop

**Do not use background monitoring agents.** The orchestrator directly runs the loop below:

```
while training process is running:
  1. stdout tail (TaskOutput block=false) → detect "[EPOCH_DONE] N/M" pattern
  2. if detected → run Per-Epoch Processing Procedure below, one epoch at a time (even if multiple accumulated)
  3. if not detected → adaptive sleep then repeat (see rules below)
```

**Per-Epoch Processing Procedure** (must complete all of the following per epoch):
1. incremental metric query → `cache/metric_cache.jsonl` append
2. `session_continuation.json` — **ATOMIC update** in a SINGLE Edit call: set `status = "pending_resume"`, update `written_at` to current ISO timestamp, AND update `mid_experiment_recovery`. Never update these separately — a partial write caused by context exhaustion must leave the file in a recoverable state.
3. inline abort decision (see rules below)
4. Edit `experiment_{N}_detail.md` directly (orchestrator records instead of scribe)
5. **GitHub sync** (Step 3 rules)

**Accumulated epoch rule**: When waking from adaptive sleep, multiple `[EPOCH_DONE]` entries may have accumulated in stdout. In this case, **process epochs one at a time in order**. Never batch multiple epochs or run sync only once at the end. Example: E4, E5, E6 accumulated → process E4+sync → process E5+sync → process E6+sync.

**Epoch detection**: match regex `\[EPOCH_DONE\] (\d+)/(\d+)` in stdout.

---

## Adaptive Sleep (key to context conservation)

- Do **not use fixed-interval sleep** when waiting for epochs. Instead, estimate epoch duration and handle most of the wait with a single sleep:
  1. **First epoch**: wait for completion using `TaskOutput block=true timeout=600000` (max 10 min, blocking). If not sufficient, then poll at 60s intervals.
  2. **2nd epoch onwards**: compute `avg_epoch_time` from previous epochs. `sleep_time = avg_epoch_time * 0.85` (sleep until 85% point in one go). Then poll at 30s intervals.
  3. **Calculation example**: if previous epoch average is 6000s → `sleep 5100` once → then 30s polling (max ~10 times). **Total polling calls: ~10/epoch** (95% reduction vs. previous ~100-200 calls).
- Compute `avg_epoch_time` from the `epoch_time_s` field in `cache/metric_cache.jsonl`.
- Before sleeping, confirm process is still alive via `TaskOutput block=false` to detect early termination.

---

## Emergency State Recording (per epoch)

- After each epoch detection, the orchestrator updates `cache/session_continuation.json` with a **SINGLE atomic Edit** that sets ALL three fields together:
  ```json
  {
    "status": "pending_resume",
    "written_at": "<current ISO 8601 timestamp>",
    "mid_experiment_recovery": {
      "experiment_n": N,
      "run_name": "current run name",
      "epochs_completed": completed_epoch_count,
      "epochs_total": total_epoch_count,
      "last_metric_step": last_step,
      "training_pid": training_process_PID,
      "status": "in_progress"
    }
  }
  ```
- **Why atomic**: if context exhausts between separate edits, the file lands in an inconsistent state (e.g., `mid_experiment_recovery` set but `status` still `"initial"`). The external loop sees `"initial"` and re-runs the experiment from scratch → **duplicate wandb run with the same name**. A single Edit prevents this.
- No separate scribe call — just update the JSON file with 1 line (context conservation).
- Even if the session terminates abnormally (e.g., context exhausted), this file persists for automatic recovery when the external wrapper restarts.
- Reset `mid_experiment_recovery` to `null` AND `status` back to `"pending_resume"` (keep it at pending_resume since we're between iteration end and next experiment) when training completes normally.

**Context defense rules**:
- If **20 or more epochs remain** and **50 or more epochs have already been processed**, record results so far in `mid_experiment_recovery` and end the iteration.
- Set `session_continuation.json`'s `status` to `"pending_resume"` and `mid_experiment_recovery.status` to `"in_progress"`. Do not stop the training process (it keeps running in background).
- When the external wrapper creates a new session, monitoring resumes with `pending_resume` + `mid_experiment_recovery` (polling restarts in a fresh context).
- This rule is a safeguard to replace only the orchestrator with a fresh context without interrupting the training process.

---

## Metric Query (incremental)

1. Read last queried step from `cache/metric_last_step.txt` (0 if not found)
2. Query logging system API (wandb: `run.scan_history(keys=[...], min_step=last_step+1)`, others: see `METRIC_FETCH_CMD` in CLAUDE.md)
3. Append result as 1 JSONL line to `cache/metric_cache.jsonl`
4. Update `cache/metric_last_step.txt`

**Fallback on metric query failure**: parse metrics directly from stdout
- Pattern: parse according to the project's stdout format. Use `EPOCH_LOG_PATTERN` from CLAUDE.md if defined. Otherwise parse based on `[EPOCH_DONE]` marker (see below)

**Information kept in orchestrator context**: 1 line per epoch (~30 tokens) — e.g., `E5: metric1=0.42 metric2=0.51 — continue`

---

## Inline Epoch Decision + Escalation

After epoch detection and metric cache update, the orchestrator **directly** checks numbers from cache to make a decision. Handle inline without Agent calls; only escalate to the quick reviewer when suspicious.

**Auto abort (immediate, no Agent call)**:
- NaN or Inf detected
- val_loss increased >3x from epoch 1 (diverging)

**Quick reviewer escalation (Agent call)**:
- val_loss increases for **5 consecutive epochs** or more
- train_loss plateaus for **5 consecutive epochs** or more (change < 1%)
- train_loss declining but gap with val_loss widening for **3 consecutive epochs** (suspected overfitting)

On escalation, call 1 quick reviewer via **sync Task**:
- **Pass file paths only in prompt** (no inline data):
  - `cache/metric_cache.jsonl`
  - `reports/experiment_{N}_detail.md`
- **Returns**: `continue` or `abort` + up to 500 chars rationale (only this loaded into orchestrator context)

**Otherwise**: `continue` (no Agent call)

※ Most normal epochs are processed immediately without Agent calls. Escalation is a safeguard for early termination of obvious failures during training; operate conservatively — **abort only when there are clear signs of failure**, default to `continue` when ambiguous.

---

## Direct Orchestrator Recording (Per Epoch)

After decision, the orchestrator **directly** appends to `experiment_{N}_detail.md` via the Edit tool. Do not call the scribe Agent.

**Normal (continue, no Agent call)**:
```markdown
#### E{N}/{total} ({elapsed}s)
`{metric_key}={val} | ... | lr={lr}` (project's key metrics)
**auto decision**: `continue`
```

**After escalation (when quick reviewer is called)**:
```markdown
#### E{N}/{total} ({elapsed}s)
`{metric_key}={val} | ... | lr={lr}` (project's key metrics)
**quick review**: `continue` — val_loss rising consecutively but still within convergence range.
```

**Auto abort**:
```markdown
#### E{N}/{total} ({elapsed}s)
`{metric_key}={val} | ... | lr={lr}` (project's key metrics)
**auto decision**: `abort` — {reason: NaN detected / val_loss diverging, etc.}
> abort details: [metric snapshot, rationale]
```

**GitHub sync immediately after recording** (per Step 3 rules). This sync **must run individually per epoch** — never batch multiple epochs into one sync.

---

## On Abort

- Stop the training process
- Save current results to `results/experiment_{N}_aborted.json`
- **Enter Step 2**: conduct normal multi-agent review based on aborted results → Step 3 (GitHub sync) → end iteration

---

## Post-Training Result Collection

- Since `cache/metric_cache.jsonl` already holds all epoch data, **no need for a full export CLI call or full API collection**.
- Generate `results/experiment_{N}.json` from `cache/metric_cache.jsonl`
- **Call scribe**: record training result summary (scribe reads numbers directly from cache files)
