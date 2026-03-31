# claude-sisyphus-grad — Project Configuration

## Required Settings (modify to fit your project)

### Experiment Environment
```
CONDA_ENV=myenv          # conda env name (default for train command env arg)
```

### Research Directory Settings
```
# If research/ is a separate git repo:
#   git -C research remote -v  to verify
# If not a separate repo, use regular git add/push
```

### Metric Query Settings (optional)
```
# Using wandb: no extra config needed (prompts use wandb API by default)
# Using custom logging: set env vars below
# METRIC_FETCH_CMD="python scripts/fetch_metrics.py --step {last_step}"
# EPOCH_LOG_PATTERN="Epoch {n}/{total} | loss={loss} | val={val}"
```

### GitHub Sync Settings (optional)
```
# Override research/ sync command (default: git push)
# RESEARCH_SYNC_CMD="bash scripts/my_sync.sh"
```

---

## Git Branch Rules
- Always create a new branch for each feature/task
- branch naming: `feat/<feature-name>`, `fix/<bug-name>`, `train/<experiment>/exp{N}-code-mod`
- Merge into main when done, delete the branch afterward
- Do not commit directly to main

## Experiment Automation
- For DL/ML experiment automation: use the `/train` command
- Detailed protocol: see `.claude/commands/train.md`

## Research Notes
- Always read `research/CLAUDE.md` before starting research discussions
- Check `research/README.md` for current research status
- Create `research/logs/YYYY-MM-DD/log.md` at the start of each day's discussion
- Use the `/discuss` command to start context-aware research discussions

---

## Project Customization Points

Adjust the following to fit your project's characteristics:

### 1. Reviewer Role Adjustment (`.claude/prompts/train-review-pipeline.md`)
Default: A(stats/metrics), B(algorithm), C(data), D(Feasibility), E(supplement), F(moderator), G(Research Innovator)
Modify, add, or remove reviewer roles based on your domain.

### 2. Abort Condition Adjustment (`.claude/prompts/train-monitor.md`)
Default abort conditions: NaN/Inf, val_loss diverges >3x
Recommended to adjust for your project's key metric.

### 3. Convergence Criteria Adjustment (`.claude/prompts/train-orchestrator-decisions.md`)
"improvement < noise level for 2+ recent experiments" → adjust to your project's metric noise characteristics.
