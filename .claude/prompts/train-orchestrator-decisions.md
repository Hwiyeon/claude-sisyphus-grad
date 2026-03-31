# Experiment Decision Principles & Code Modification Procedure (Lazy-loaded)

> This module is Read from `train-orchestrator.md` only when needed.
> - Before Judge decision: reference Strict Convergence + Bold Improvement principles
> - Before algo_modify execution: reference algorithm/code modification procedure

---

## Strict Convergence Principle (default)

- `go` means "sufficiently converged within the current approach", but apply that judgment **strictly**.
- To choose `go`, **all** of the following conditions must be met:
  1. Improvement in the key metric is below noise level for 2+ recent experiments (judge based on project's key_metric)
  2. Both config modifications and algorithm modifications have been attempted and show no improvement — do not choose `go` when only config has been tuned without attempting structural improvements
  3. A majority of reviewers A–F cannot propose further improvements, and G's research brief shows no promising alternatives
- If any reviewer proposes structural improvements (architecture changes, loss function redesign, data pipeline improvements, etc.), **always** choose `algo_modify`. Do not give up on bold improvements as long as `max_experiments` budget remains.

---

## Bold Improvement Principle (default)

- Every time config tuning reaches its limits, attempt fundamental improvements **without hesitation**:
  - Model architecture changes (layer structure, attention mechanism, embedding approach, etc.)
  - Loss function redesign or replacement
  - Dataset pipeline improvements (preprocessing, augmentation, sampling strategy, etc.)
  - Training strategy changes (curriculum learning, multi-stage training, etc.)
- These large changes are made following the existing `algorithm/code modification procedure` — branch isolation, GitHub recording.
- If 2+ rounds of config fine-tuning produce no meaningful improvement, the next experiment must attempt structural modifications.

---

## Algorithm/Code Modification Procedure (automatic, no user intervention)

When review conclusion is `algo_modify`, perform the following automatically **without user confirmation**:

1. **Derive modification scope**: compile the specific changes from the reviewer discussion (architecture changes, loss function modifications, module additions, etc.)
2. **Execute common procedure**: Read `.claude/prompts/train-code-modifier.md` and follow the common procedure.
   - `{input_file}`: `reports/experiment_{N}_detail.md`
   - `{branch_name}`: `train/{experiment_title}/exp{N}-code-mod`
   - `{record_targets}`: `session_report.md` + `experiment_{N}_detail.md`
3. **Return to Step 0**: start a new experiment with the modified code (skip scribe initialization)

※ `algo_modify` includes not only config changes but also **source code modifications to model code, loss functions, data pipelines, etc.** Code modifications and retraining may be repeated as many times as needed within the `max_experiments` budget.
※ Users can review the branch list in `session_report.md` after training and use `git diff`, `git log`, rollback (`git revert`), etc. to post-hoc analyze each code modification.
