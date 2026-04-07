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

**Do not use background monitoring agents.** The orchestrator directly runs the loop below.

### Monitoring Source: training_log.txt (NOT stdout)

**CRITICAL**: Do NOT poll stdout (TaskOutput) for epoch detection. The training script's stdout contains tqdm progress bars that produce ~100KB per epoch, which floods the orchestrator context.

Instead, monitor the **training log file** written by the training script:
- **Log file path**: read `output_dir` from the config file → `{output_dir}/{run_name}/training_log.txt`
- The training script appends 1 line per epoch + `[EPOCH_DONE] N/M` marker
- Use `tail` or `grep` via Bash to read only new lines, not the Read tool (which returns full content)

**Epoch detection command** (use Bash tool):
```bash
grep '\[EPOCH_DONE\]' {log_file_path} | tail -1
```
To find new epochs since last check:
```bash
grep '\[EPOCH_DONE\]' {log_file_path} | awk -F'[] /[]' '{print $2}' | tail -n +{last_seen+1}
```

**stdout is only used for**: checking if the training process has terminated (TaskOutput block=false, check exit code). Never parse stdout content for metrics — it's polluted by tqdm.

### Polling Loop

```
# Track last processed epoch number (start at 0, or mid_experiment_recovery.epochs_completed)
last_epoch = 0

while training process is running:
  0. check {session_dir}/cache/stop_signal.json → if exists, enter Stop Signal Handling below
  1. grep [EPOCH_DONE] from training_log.txt → find epochs > last_epoch
  2. if new epochs found → run Per-Epoch Processing Procedure below, one epoch at a time
  3. if no new epochs → adaptive sleep then repeat (see rules below)
  4. confirm process alive: kill -0 {pid} (Bash) — if dead, collect final results
```

**Per-Epoch Processing Procedure** (must complete all of the following per epoch):
1. parse metrics from the log line preceding `[EPOCH_DONE]` → `cache/metric_cache.jsonl` append
2. `session_continuation.json` — **ATOMIC update** in a SINGLE Edit call: set `status = "pending_resume"`, update `written_at` to current ISO timestamp, AND update `mid_experiment_recovery`. Never update these separately — a partial write caused by context exhaustion must leave the file in a recoverable state.
3. inline abort decision (see rules below)
4. Edit `experiment_{N}_detail.md` directly (orchestrator records instead of scribe)
5. **GitHub sync** (Step 3 rules)

**Accumulated epoch rule**: When waking from adaptive sleep, multiple `[EPOCH_DONE]` entries may have accumulated. In this case, **process epochs one at a time in order**. Never batch multiple epochs or run sync only once at the end. Example: E4, E5, E6 accumulated → process E4+sync → process E5+sync → process E6+sync.

**Epoch detection**: match regex `\[EPOCH_DONE\] (\d+)/(\d+)` in training_log.txt.

---

## Adaptive Sleep (key to context conservation)

- Do **not use fixed-interval sleep** when waiting for epochs. Instead, estimate epoch duration and handle most of the wait with a single sleep:
  1. **First epoch**: `sleep 300` (5 min default), then poll at 60s intervals.
  2. **2nd epoch onwards**: compute `avg_epoch_time` from previous epochs. `sleep_time = avg_epoch_time * 0.85` (sleep until 85% point in one go). Then poll at 30s intervals.
  3. **Calculation example**: if previous epoch average is 6000s → `sleep 5100` once → then 30s polling (max ~10 times). **Total polling calls: ~10/epoch** (95% reduction vs. previous ~100-200 calls).
- Compute `avg_epoch_time` from the `epoch_time_s` field in `cache/metric_cache.jsonl`.
- **avg_epoch_time must only include successful training epochs**. Exclude failed attempts (OOM crashes, setup time, etc.) from the calculation. If no valid epoch time data exists yet, use 300s as default.
- Before sleeping, confirm process is still alive via `kill -0 {pid}` (Bash) to detect early termination.

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
2. **Primary**: parse metrics from training_log.txt — the log line immediately before `[EPOCH_DONE] N/M` contains all epoch metrics in a structured format. Use `grep` or `sed` to extract the relevant line.
3. Append result as 1 JSONL line to `cache/metric_cache.jsonl`
4. Update `cache/metric_last_step.txt`

**Fallback**: if training_log.txt is unavailable, query logging system API (wandb: `run.scan_history(keys=[...], min_step=last_step+1)`)

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

## Stop Signal Handling

When `{session_dir}/cache/stop_signal.json` is detected during the polling loop, the user has requested a graceful stop from their interactive session.

Read the file and branch by `mode`:

### `mode=immediate`

1. Kill the training process (`kill {training_pid}`)
2. Update `session_continuation.json`: set `status` to `"stopped"`, update `written_at`
3. **End response immediately** — do not perform any recording or review

### `mode=report`

1. Kill the training process (`kill {training_pid}`)
2. Collect current metrics from `cache/metric_cache.jsonl` → save to `results/experiment_{N}_stopped.json`
3. Call scribe to write a session report summary in `session_report.md`:
   ```markdown
   ---
   ## Stopped by User (YYYY-MM-DD HH:MM:SS)
   - Mode: report
   - Stopped at: Experiment {N}, Epoch {completed}/{total}
   - Last metrics: {key metrics summary}
   ---
   ```
4. Update `session_continuation.json`: set `status` to `"stopped"`, update `written_at`
5. GitHub sync
6. **End response immediately**

### `mode=review`

1. Kill the training process (`kill {training_pid}`)
2. Collect current metrics from `cache/metric_cache.jsonl` → save to `results/experiment_{N}_stopped.json`
3. Record training stop in `experiment_{N}_detail.md`
4. **Enter Step 2**: conduct full multi-agent review based on stopped results (same as On Abort flow)
5. After review completes, update `session_continuation.json`: set `status` to `"stopped"`, update `written_at`
6. GitHub sync
7. **End response immediately**

※ In all modes, after the orchestrator sets `status` to `"stopped"`, `train-loop.sh` will detect this and exit the loop automatically.
※ Do **not** delete `stop_signal.json` — it serves as an audit trail.

---

## Post-Training Result Collection

- Since `cache/metric_cache.jsonl` already holds all epoch data, **no need for a full export CLI call or full API collection**.
- Generate `results/experiment_{N}.json` from `cache/metric_cache.jsonl`
- **Call scribe**: record training result summary (scribe reads numbers directly from cache files)
