# Experiment Automation Launcher (External Script Loop)

This command parses arguments, creates the initial state, and runs `scripts/train-loop.sh` in the background to automatically repeat the experiment loop.
Detailed orchestrator rules are defined in `.claude/prompts/train-orchestrator.md`.

---

## Step 1: Parse Input Arguments ($ARGUMENTS)

Parse arguments in the format below. Use defaults for unspecified items:

```
/train script=world_model/pretrain.py config=configs/pretrain_config.yaml max_experiments=20 experiment_title="transformer_baseline" env=myenv parallel=1 instructions="adjust lr based on previous run report before starting"
```

| argument | description | default |
|----------|-------------|---------|
| `script` | path to training script | required |
| `config` | path to config file for training | required |
| `experiment_title` | experiment title (used as folder name) | required |
| `max_experiments` | maximum number of experiments | 20 |
| `review_cycles` | number of G Research Brief → round 2 → round 3 → Judge decision cycle repetitions | 1 |
| `goal` | experiment termination condition (metric-based) | optional |
| `decision_criteria` | decision criteria (free text or `@filepath`) | optional |
| `env` | Python virtual environment name (training runs after `conda activate {env}`) | required |
| `parallel` | number of models to train simultaneously. If >=2, each runs as a separate parallel process | `1` |
| `instructions` | pre-instructions for the orchestrator before training. Free text or `@filepath` to reference previous reports. Multiple files: `@path1 @path2` | optional |
| `analyze` | before training, analyze best model performance, training reports, and research logs to derive and apply improvements. May include fundamental changes to architecture, loss, data pipeline, etc. | `false` |
| `subset` | if `true`, first validate with 20% subset, then switch to full dataset if promising | `false` |
| `circuit_breaker` | if the same Judge decision type occurs N times consecutively, pass pattern detection to the Judge during round 2 review to strengthen decision direction. null disables this | `null` |

After parsing, print the parsed values once for user confirmation before starting.

---

## Step 2: Pre-Validation

### A. Existing Session Detection
Check whether `research/logs/{today's date}/{experiment_title}/cache/session_continuation.json` exists:

- **Exists with `status == "pending_resume"` or `status == "analyzed"`**:
  - Print `"✅ Resuming existing incomplete session."`
  - Use existing session_continuation.json as-is (do not create a new one)
  - Proceed directly to Step 3
- **Exists with `status == "completed"` or `status == "stopped"`**:
  - Print `"ℹ️ Previous session completed. Starting a new session."`
  - Create new session_continuation.json (see Step 3-A below)
- **Does not exist**:
  - Create new session_continuation.json (see Step 3-A below)

---

## Step 3: Create Initial State

### A. Create session_continuation.json (new sessions only)

Path: `research/logs/{YYYY-MM-DD}/{experiment_title}/cache/session_continuation.json`

Create directories if they don't exist: `research/logs/{YYYY-MM-DD}/{experiment_title}/cache/`, `results/`, `reports/`

```json
{
  "schema_version": 2,
  "status": "initial",
  "written_at": "{ISO 8601 timestamp}",
  "session": {
    "experiment_title": "{experiment_title}",
    "date": "{YYYY-MM-DD}",
    "session_dir": "research/logs/{YYYY-MM-DD}/{experiment_title}",
    "script": "{script}",
    "config": "{config}",
    "env": "{env}",
    "goal": "{goal or null}",
    "max_experiments": {max_experiments},
    "review_cycles": {review_cycles},
    "parallel": {parallel},
    "instructions": "{instructions or null}",
    "decision_criteria": "{decision_criteria or null}",
    "analyze": "{analyze boolean}",
    "subset": "{subset boolean}",
    "circuit_breaker": "{circuit_breaker or null}"
  },
  "progress": {
    "experiments_completed": 0,
    "next_experiment_n": 1,
    "next_run_name": "{YYYYMMDD}-v01",
    "current_git_branch": null,
    "subset_phase": "{'subset' if subset is true, null if false}",
    "decision_history": []
  },
  "next_action": null,
  "mid_experiment_recovery": null,
  "handoff_summary": {
    "last_judge_rationale": null,
    "key_hypothesis": null,
    "failed_approaches": [],
    "critical_unknowns": []
  }
}
```

### B. Print Confirmation Message

```
🔄 Starting experiment automation with external script loop.

Experiment title: {experiment_title}
Script: {script}
Config: {config}
Max experiments: {max_experiments}

State file: research/logs/{date}/{experiment_title}/cache/session_continuation.json

A new session is created each iteration to ensure a fresh context.
Loop log: research/logs/{date}/{experiment_title}/cache/loop.log
```

---

## Step 4: Run train-loop.sh in Background

Once session_continuation.json is created and the confirmation message is printed, run `scripts/train-loop.sh` **via the Bash tool with `run_in_background=true`**:

```bash
./scripts/train-loop.sh "script={script} config={config} max_experiments={max_experiments} experiment_title={experiment_title} env={env} analyze={analyze} subset={subset}"
```

※ Include all parsed non-null arguments in the argument string (goal, instructions, decision_criteria, etc.).

After running, print the message below and exit:
```
✅ train-loop.sh has been started in the background.
You can continue other work in this session.
Check loop status: cat research/logs/{date}/{experiment_title}/cache/loop.log
```

All subsequent experiment loops are automatically managed by `train-loop.sh`, which creates a new `claude -p` session each iteration.
