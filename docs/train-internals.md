**English** | [한국어](train-internals.ko.md)

# `/train` Internals

> Referenced from [README.md](../README.md)

---

## Usage

### Basic usage
```
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

### With goal and hints
```
/train script=train.py config=configs/exp.yaml max_experiments=15 experiment_title="attention_ablation" env=myenv \
  goal="maximize val accuracy above 92% while keeping params under 50M" \
  instructions="start by testing learning rate schedule variants before touching architecture"
```

### Parallel runs (e.g. hyperparameter sweep)
```
/train script=train.py config=configs/sweep.yaml max_experiments=20 experiment_title="lr_sweep" env=myenv parallel=3
```

### Two-phase strategy (fast subset first, then full data)
```
/train script=train.py config=configs/exp.yaml max_experiments=10 experiment_title="subset_trial" env=myenv subset=true
```

### Arguments

| Argument | Description | Default |
|---|---|---|
| `script` | Training script path | required |
| `config` | Config file path | required |
| `max_experiments` | Max iterations | required |
| `experiment_title` | Session name (used for directory/branch naming) | required |
| `env` | Conda environment name | required |
| `parallel` | Number of parallel runs | `1` |
| `subset` | Use subset→full two-phase strategy | `false` |
| `goal` | What "good" looks like (natural language) | — |
| `instructions` | Starting hints for the orchestrator | — |
| `circuit_breaker` | N consecutive same-type decisions triggers alert | — |

---

## How the loop works

```
User runs /train
      │
      ▼
scripts/train-loop.sh  ──── spawns claude -p per iteration ────┐
      │                                                          │
      │  ┌──────────────────────────────────────────────────────┘
      │  │  Claude session (orchestrator)
      │  │    reads session_continuation.json
      │  │    ├─ status=initial  → initialize directories, run training
      │  │    ├─ status=analyzed → skip pre-analysis, run training
      │  │    └─ status=pending_resume → apply next_action, run training
      │  │
      │  │  Training runs
      │  │    monitors stdout / wandb for metrics
      │  │    writes metric_cache.jsonl per epoch
      │  │    abort if NaN / loss divergence detected
      │  │
      │  │  Multi-agent review
      │  │    G research brief (WebSearch) → Round 2 → Round 3 → Judge
      │  │
      │  │  Writes session_continuation.json with next_action
      │  │  Writes session_report.md update
      │  │  Exits (prints iteration marker)
      │  │
      └──┴─ train-loop.sh reads marker, spawns next session
```

Each Claude session is stateless — all state is persisted in `session_continuation.json` and the experiment files under `research/logs/`.

---

## State file: `session_continuation.json`

The orchestrator's persistent state across iterations. Written at the end of each session, read at the start of the next.

```json
{
  "session": {
    "script": "train.py",
    "config": "configs/exp.yaml",
    "env": "myenv",
    "goal": "maximize val_acc above 92%",
    "max_experiments": 10,
    "review_cycles": 1,
    "parallel": 1,
    "subset": false,
    "experiment_title": "baseline_v1",
    "instructions": null,
    "circuit_breaker": null
  },
  "status": "initial | analyzed | pending_resume | completed | stopped",
  "progress": {
    "next_experiment_n": 3,
    "next_run_name": "exp3_algo_mod",
    "decision_history": ["go", "config_modify", "algo_modify"],
    "current_git_branch": "train/baseline_v1/exp2-code-mod",
    "subset_phase": null
  },
  "next_action": {
    "type": "config_modify | algo_modify | subset_to_full",
    "config_changes": [
      { "key": "optimizer.lr", "value": 0.0005, "reason": "plateau after epoch 12" }
    ],
    "algo_changes": "add residual connection in encoder block 3–6"
  },
  "handoff_summary": {
    "last_judge_rationale": "val_loss plateau + reviewer B identified missing skip connection",
    "key_hypothesis": "residual connections will stabilize gradient flow in deeper layers",
    "failed_approaches": ["lr warmup", "dropout increase to 0.3"],
    "best_metric_so_far": { "val_acc": 0.873, "experiment_n": 1 }
  }
}
```

### Status values

| Status | Meaning |
|---|---|
| `initial` | First iteration; orchestrator initializes directories and starts experiment 1 |
| `analyzed` | Pre-analysis (`/analyze`) completed; ready to start experiment 1 |
| `pending_resume` | Previous iteration completed; `next_action` is ready to execute |
| `completed` | Loop finished normally (`go` decision or `max_experiments` reached) |
| `stopped` | Aborted by user or unrecoverable error |

---

## What `algo_modify` does

When the Judge decides `algo_modify`:

1. The orchestrator reads `.claude/prompts/train-orchestrator-decisions.md` for the code modification procedure
2. A new git branch is created: `train/{experiment_title}/exp{N}-code-mod`
3. The Code Modifier agent reads the review transcript and applies source code changes autonomously (no user confirmation)
4. Changes may include: model architecture, loss function, data pipeline
5. The branch is pushed; `session_continuation.json` records the branch name
6. The next iteration runs training on the modified code

You can review, diff, or roll back any branch after the session ends.

---

## Metric collection

The orchestrator monitors metrics during training via two sources (in priority order):

1. **wandb** — if available, queries the wandb API for per-step metrics
2. **stdout parsing** — falls back to parsing training script stdout for patterns like `epoch={N} loss={x} val_loss={x}`

Metrics are written to `cache/metric_cache.jsonl` per epoch. The abort conditions (NaN, loss divergence 3×) are checked in real time.

Custom metric patterns can be configured via `METRIC_FETCH_CMD` or `EPOCH_LOG_PATTERN` in `CLAUDE.md`.

---

## Experiment files

Each experiment writes to `research/logs/YYYY-MM-DD/{experiment_title}/`:

```
results/
  experiment_{N}.json          ← final metrics + config snapshot
  experiment_{N}_aborted.json  ← written instead if abort triggered
reports/
  session_report.md            ← cumulative session log (all experiments)
  experiment_{N}_detail.md     ← full detail: training log + review transcript
  research_brief_{N}.md        ← G's web search output
  pre_analysis_briefing.md     ← written by /analyze (if used)
cache/
  metric_cache.jsonl           ← per-epoch metrics (JSONL)
  metric_last_step.txt         ← last polled step (for incremental polling)
```
