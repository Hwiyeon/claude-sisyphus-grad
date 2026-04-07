# Stop / Reset — Experiment Shutdown & Cleanup

> This module is loaded from `train.md` when `$ARGUMENTS` starts with `stop` or `reset`.

## Parse Stop Arguments

```
/train stop mode=review                          ← full review before exit
/train stop mode=report                          ← session report only
/train stop mode=immediate                       ← kill and exit instantly
/train stop mode=review experiment_title=foo     ← target specific session
```

| argument | description | default |
|----------|-------------|---------|
| `mode` | `review`, `report`, or `immediate` | **required** |
| `experiment_title` | target session (when multiple active today) | auto-detect if only one |

---

## Step S1: Find Active Session

1. List directories under `research/logs/{today's date}/`
2. For each, check `cache/session_continuation.json` — find sessions with `status` NOT in `["completed", "stopped"]`
3. **One active session found** → use it
4. **Multiple active sessions** → if `experiment_title` is specified, use it. Otherwise, list them and ask the user to specify
5. **No active session found** → print `"⚠️ No active experiment session found for today."` and exit

---

## Step S2: Write Stop Signal

Write `{session_dir}/cache/stop_signal.json`:

```json
{
  "mode": "{review|report|immediate}",
  "requested_at": "{ISO 8601 timestamp}"
}
```

---

## Step S3: Branch by Mode

### `mode=immediate`

The orchestrator may not poll in time, so act directly:

1. **Kill training process**: read `mid_experiment_recovery.training_pid` from `session_continuation.json`. If present and alive (`kill -0`), kill it (`kill {pid}`)
2. **Kill train-loop.sh**: find the loop process via `pgrep -f "train-loop.sh.*{experiment_title}"` and kill it
3. **Update state**: set `session_continuation.json` `status` to `"stopped"`, update `written_at`
4. Print:
   ```
   ⛔ Experiment "{experiment_title}" stopped immediately.
   State: {session_dir}/cache/session_continuation.json
   ```

### `mode=review` or `mode=report`

Act directly from the user session — do NOT wait for the orchestrator to detect the stop signal. The orchestrator may be in a long adaptive sleep and unable to respond in time.

1. **Kill training process**: read `mid_experiment_recovery.training_pid` from `session_continuation.json`. If present and alive (`kill -0`), kill it (`kill {pid}`)
2. **Kill train-loop.sh**: find the loop process via `pgrep -f "train-loop.sh.*{experiment_title}"` and kill it. Also kill the orchestrator claude process if found via `pgrep -f "claude.*-p.*{experiment_title}"` (it may be stuck in adaptive sleep)
3. **Sync metric_cache from training_log.txt**: the orchestrator may not have recorded all completed epochs. Before review/report, sync any missing epochs:
   - Read the config to find `output_dir` → locate `{output_dir}/{run_name}/training_log.txt`
   - Read `cache/metric_last_step.txt` to find last recorded epoch
   - Parse any newer `Epoch N/M | ...` lines from training_log.txt
   - Append missing epochs to `cache/metric_cache.jsonl` as JSONL
   - Update `cache/metric_last_step.txt`
   - Update `mid_experiment_recovery.epochs_completed` in `session_continuation.json`
   - Also append missing epoch entries to `reports/experiment_{N}_detail.md`
4. **Branch by mode**:

   **`mode=report`**:
   - Call scribe agent to write session report summary in `reports/session_report.md` (pass file paths for metric_cache, experiment_detail, session_continuation)
   - Update `session_continuation.json`: set `status` to `"stopped"`, update `written_at`
   - GitHub sync
   - Print:
     ```
     📊 Session report written for "{experiment_title}".
     Report: {session_dir}/reports/session_report.md
     ```

   **`mode=review`**:
   - Save current results to `results/experiment_{N}_stopped.json` (from metric_cache.jsonl)
   - Read `.claude/prompts/train-review-pipeline.md` and execute the full multi-agent review pipeline (Reviewers A-G, Judge) using the collected results
   - Record review results in `reports/experiment_{N}_detail.md`
   - Update `session_continuation.json`: set `status` to `"stopped"`, update `written_at`
   - GitHub sync
   - Print:
     ```
     🔍 Review complete for "{experiment_title}".
     Detail: {session_dir}/reports/experiment_{N}_detail.md
     ```

---

# Reset Mode

Triggered when `$ARGUMENTS` starts with `reset`. Performs immediate stop + full cleanup so the experiment can be restarted from scratch.

```
/train reset experiment_title=foo
```

| argument | description | default |
|----------|-------------|---------|
| `experiment_title` | target session | auto-detect if only one today |

## Procedure

1. **Find session**: same as Stop Mode Step S1
2. **Stop** (if still running): execute the `mode=immediate` procedure from Stop Mode (kill training, kill train-loop.sh)
3. **Confirm with user**: print the list of artifacts to be deleted and ask for confirmation:
   ```
   🗑️ Reset will delete the following for "{experiment_title}":
   - Session dir: research/logs/{date}/{experiment_title}/ (cache, reports, results)
   - Output dir: {output_dir}/{run_name}/ (checkpoints, wandb_run_id.txt, saved config)
   - wandb runs matching: {run_name_pattern} (YYYYMMDD-v*)

   Proceed? (y/n)
   ```
4. **Run Cleanup Procedure** (see below)
5. Print:
   ```
   ✅ Reset complete for "{experiment_title}". Ready for a fresh /train.
   ```

---

# Cleanup Procedure

Shared by both `/train reset` and `/train ... clean=true`. Always requires user confirmation before execution.

## What gets cleaned

| Target | Action | How |
|--------|--------|-----|
| **Session directory** | Delete entire `research/logs/{date}/{experiment_title}/` | `rm -rf {session_dir}` |
| **wandb runs** | Delete runs matching this session's run names | Read `run_name` patterns from `session_continuation.json` `progress` field. Use `wandb run delete {entity}/{project}/{run_id}` via API, or `rm -rf wandb/` local dir if offline mode |
| **Checkpoints & output dir** | Delete checkpoints and wandb state created by this session | Check config file for checkpoint output path. Delete the `{output_dir}/{run_name}/` directory (includes `wandb_run_id.txt`, saved configs, checkpoints) |
| **train-loop.sh process** | Kill if alive | `pgrep -f "train-loop.sh.*{experiment_title}"` |
| **Training process** | Kill if alive | `mid_experiment_recovery.training_pid` from state file |

## Safety rules

- **Never delete without confirmation**: always print what will be deleted and wait for user approval
- **Scope guard**: only delete artifacts matching the specific `experiment_title` and date. Never use broad wildcards
- **Config file is preserved**: the training config (`configs/*.yaml`) is never deleted
- **Git branches are preserved**: branches created by `algo_modify` are not deleted (user may want to review them). Print a note listing any related branches:
  ```
  ℹ️ Git branches from this session (not deleted): train/exp1-foo, train/exp2-bar
  ```
