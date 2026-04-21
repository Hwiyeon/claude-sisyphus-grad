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

- run_name is generated in `{experiment_title}/{YYYYMMDD}_v{experiment_number 2-digit}` format (e.g., `ego_dropout/20240315_v01`)
  - Use `progress.next_wandb_run_name` if present
- Write run_name directly into the logging name field in config file, then run training (when using wandb etc.):
  ```bash
  source /home/hwing/miniforge3/etc/profile.d/conda.sh && conda activate {env} && python {script} --config {config}
  ```
  **CRITICAL — launch method**: MUST use `conda activate && python` as shown above. **NEVER use `conda run`** — it wraps stdout in pipes, breaking `claude-train-watch` fd-based process attachment. The training process's fd/1 must point to the Bash tool's task output file (a regular file), not a pipe.
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

**Do not use background monitoring agents** (Task/Agent with `run_in_background`). The orchestrator monitors via a background **Bash** polling script (a shell process, not an agent context) paired with foreground cache-warming sleeps. The model never delegates monitoring logic to a subagent.

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

### Polling Loop (Background Bash + Foreground Cache Warming)

The polling loop uses two parallel tracks to minimize API calls while keeping the prompt cache warm:
- **Background Bash** (`run_in_background`): a shell script that polls `training_log.txt` internally every 15 seconds. Zero API calls — the shell does the waiting.
- **Foreground cache warming**: `sleep 240` + single-token `"."` output every ~240 seconds, keeping the prompt cache alive.

```
# Track last processed epoch number (start at 0, or mid_experiment_recovery.epochs_completed)
last_epoch = 0
LOG = {output_dir}/{run_name}/training_log.txt
PID = training process PID

while training process is running:
  0. check {session_dir}/cache/stop_signal.json → if exists, enter Stop Signal Handling below

  1. LAUNCH BACKGROUND MONITOR — Bash(run_in_background=true):
       timeout {poll_timeout} bash -c '
         LAST={last_epoch}
         while true; do
           NEW=$(grep -c "\[EPOCH_DONE\]" "{LOG}" 2>/dev/null || echo 0)
           if [ "$NEW" -gt "$LAST" ]; then echo "EPOCH $NEW"; exit 0; fi
           if ! kill -0 {PID} 2>/dev/null; then echo "CRASH"; exit 1; fi
           if [ -f /proc/{PID}/status ] && grep -q "^State:.*Z" /proc/{PID}/status 2>/dev/null; then
             echo "CRASH zombie"; exit 1
           fi
           sleep 15
         done
       ' || echo "TIMEOUT"

  2. CACHE-WARMING FOREGROUND — while background monitor has not completed:
       Bash(sleep 240)
       output "."                    ← single token, keeps prompt cache alive
       check {session_dir}/cache/stop_signal.json → if exists, kill background task, enter Stop Signal Handling
       check if background task completed → if yes, break

  3. READ BACKGROUND RESULT:
       "EPOCH N" → find new epochs > last_epoch → run Per-Epoch Processing below, one epoch at a time
       "CRASH" or "CRASH zombie" → enter Crash Handling Procedure below
       "TIMEOUT" → loop back to step 1 (re-launch background monitor with same last_epoch)

  4. update last_epoch → loop back to step 1
```

**Per-Epoch Processing Procedure** — delegated to a **foreground subagent** to keep the orchestrator's main context clean:

When new epochs are detected, call `Agent(subagent_type="general-purpose")` with the following inputs in the prompt:
- `epoch_range`: epochs to process (e.g., `[5, 6, 7]`)
- `log_path`: path to `training_log.txt`
- `session_dir`: session directory path
- `experiment_n`: current experiment number
- `run_name`: current run name
- `config_path`: config file path (for reading `output_dir`)
- `training_pid`: PID of the training process
- `metric_cache_path`: path to `cache/metric_cache.jsonl`
- `session_continuation_path`: path to `session_continuation.json`

The subagent executes **all 5 steps per epoch**, one epoch at a time:
1. parse metrics from the log line preceding `[EPOCH_DONE]` → `cache/metric_cache.jsonl` append
2. `session_continuation.json` — **ATOMIC update** in a SINGLE Edit call: set `status = "pending_resume"`, update `written_at` to current ISO timestamp, AND update `mid_experiment_recovery`. Never update these separately.
3. inline abort decision (NaN/Inf → auto abort, 5+ consecutive val_loss increase → escalate to quick reviewer within the subagent)
4. Edit `experiment_{N}_detail.md` (recording format unchanged — see Direct Orchestrator Recording section below)
5. **GitHub sync** — follow Step 3 batched trigger rules: run `git commit && push` only when this epoch is a trigger (every 5th epoch, new-best, escalation, abort). Otherwise skip — the Edit in step 4 is already on disk and will be included in the next batched sync.

**Subagent return format** (this is ALL that enters the main orchestrator context):
```
E5: continue | val_loss=0.42 spearman=0.51
E6: continue | val_loss=0.40 spearman=0.53
E7: abort (NaN) | val_loss=NaN
```
One line per epoch, ≤30 tokens per line. If any epoch returns `abort`, the orchestrator enters the On Abort flow.

**Accumulated epoch rule**: When the background monitor returns "EPOCH N" with N > last_epoch + 1, pass all accumulated epochs to a **single subagent call**. The subagent processes them one at a time in order internally (E4 record → E5 record → E6 record+sync). Sync follows the batched trigger rules (see orchestrator Step 3) — typically one commit covering multiple epochs per batch, rather than a commit per epoch.

**Epoch detection**: match regex `\[EPOCH_DONE\] (\d+)/(\d+)` in training_log.txt.

### Output Verbosity Rules (Token Conservation)

Output tokens are **not cacheable** — every token of model text output is billed at full rate and counts toward rate limits. Apply these rules to all text output between tool calls during the polling loop:

1. Text output between tool calls: **≤10 tokens**. No status narration, no progress commentary.
2. Acceptable: `"."`, `"E6 done"`, `"chk stop"`, `"timeout, retry"`.
3. Unacceptable: `"E6 at 43% (251/588, 2:34 elapsed). ~210s remaining."`.
4. Per-epoch processing output: **subagent handles all file writes**. Orchestrator only receives the 1-line-per-epoch summary.
5. Epoch inline decision format (from subagent return): `"E6: continue"` or `"E6: abort (NaN)"` — one short line.

---

## Crash Handling Procedure

When the background Bash monitor returns "CRASH" or "CRASH zombie":

1. **Confirm termination**: `kill -0 {PID}` via Bash — expected to fail (process already dead). If still alive (zombie case), `kill -9 {PID}`.
2. **Collect last epoch**: `grep '\[EPOCH_DONE\]' {LOG} | tail -1` — determine last successfully completed epoch.
3. **Save partial results**: generate `results/experiment_{N}_aborted.json` from `cache/metric_cache.jsonl` (all epochs collected so far).
4. **Atomic state update**: `session_continuation.json` — SINGLE Edit call:
   - `status`: `"pending_resume"`
   - `written_at`: current ISO timestamp
   - `mid_experiment_recovery.status`: `"crashed"`
   - `mid_experiment_recovery.epochs_completed`: last completed epoch number
5. **Record in detail file**: Edit `experiment_{N}_detail.md`:
   ```markdown
   #### CRASH detected after E{last_epoch}/{total}
   Training process (PID {PID}) terminated unexpectedly.
   Last metrics: `{key}={val} | ...`
   **auto decision**: `abort` — process crash
   ```
6. **GitHub sync** (Step 3 rules)
7. **Enter Step 2**: On Abort flow — conduct multi-agent review based on partial results.

**Crash detection coverage**:
- `kill -0` detects all process terminations: OOM kill, segfault, user kill, normal exit
- Zombie check (`/proc/{PID}/status` State=Z) catches processes whose parent hasn't called `wait()`
- Detection latency: max 15 seconds (background Bash polling interval)

---

## Poll Timeout Calculation

- Do **not use fixed-interval sleep** for foreground waiting. The background Bash handles all polling internally. The orchestrator only needs to set the correct `poll_timeout` for the background script's `timeout` command:
  1. **First epoch**: `poll_timeout = 540` (9 minutes).
  2. **2nd epoch onwards**: `poll_timeout = min(ceil(avg_epoch_time * 1.2), 540)`.
  3. **On TIMEOUT**: the background monitor exits with "TIMEOUT". The orchestrator immediately re-launches a new background monitor with the same `last_epoch` — no epoch data is lost. This handles epochs longer than 9 minutes seamlessly.
- Compute `avg_epoch_time` from the `epoch_time_s` field in `cache/metric_cache.jsonl`.
- **avg_epoch_time must only include successful training epochs**. Exclude failed attempts (OOM crashes, setup time, etc.) from the calculation. If no valid epoch time data exists yet, use `poll_timeout = 540`.
- **Cache-warming interval**: fixed at **240 seconds**. This keeps the prompt cache alive under both 1-hour TTL (current, with telemetry) and 5-minute TTL (fallback). No configuration needed.
- **API calls per epoch**: typically 3–4 (launch background + 1–2 cache-warming pings + read result), vs. ~30 with the previous polling approach.

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

**Context defense rules**: DISABLED — per-epoch processing is delegated to subagents, so the main orchestrator context grows at ~150 tokens/epoch instead of ~1,100. The previous 50-epoch forced iteration cutoff is no longer needed. The orchestrator can monitor 100+ epochs within a single iteration without context pressure.

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

These rules are executed **inside the per-epoch subagent**, not in the main orchestrator. The subagent checks metrics from cache to make a decision:

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

## Per-Epoch Recording Format (executed by subagent)

The per-epoch subagent appends to `experiment_{N}_detail.md` via the Edit tool. These formats are included in the subagent prompt so it knows the recording conventions:

**Normal (continue)**:
```markdown
#### E{N}/{total} ({elapsed}s)
`{metric_key}={val} | ... | lr={lr}` (project's key metrics)
**auto decision**: `continue`
```

**After escalation (when quick reviewer is called within subagent)**:
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

**GitHub sync follows the batched trigger rules** (per orchestrator Step 3). Edits to `experiment_{N}_detail.md` land on disk immediately (crash-safe), but `git commit && push` only runs on the trigger points defined in Step 3 — every 5 epochs during normal training, or immediately on new-best / escalation / abort / crash. Do not push on every epoch.

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
