# Code Modifier Agent Procedure (Shared Module)

> This module is referenced from two places:
> - `train-orchestrator-decisions.md` — runs after algo_modify decision
> - `train-recording-rules.md` — runs after analyze mode pre-analysis
>
> The caller provides the variable values below and follows the common procedure.

---

## Caller-Provided Variables

| Variable | algo_modify | analyze mode |
|----------|-------------|--------------|
| `{input_file}` | `reports/experiment_{N}_detail.md` | `reports/pre_review_discussion.md` |
| `{branch_name}` | `train/{experiment_title}/exp{N}-code-mod` | `train/{experiment_title}/pre-analyze-mod` |
| `{record_targets}` | `session_report.md` + `experiment_{N}_detail.md` | end of `pre_review_discussion.md` |

---

## Common Procedure (automatic, no user confirmation)

1. **Create branch**: before any code modification, create `{branch_name}` branch from current state.
   Preserves pre-modification state — user can diff, approve, or rollback afterward.

2. **Call Code Modifier agent** (delegate via Task tool, orchestrator does not modify directly):
   - **Input** (pass as file paths):
     - `{input_file}` — full review discussion (includes Judge decision NEXT_ACTION)
     - Path to target code file (`{script}` and related model definition files)
     - `{config}`
   - **Evidence-first (required before making any modification)**: before modifying code, follow this order:
     1. Read the entire target file
     2. Read related files (import chain, inherited classes, shared utilities)
     3. Record current structure in 1 line (e.g., `"current Model forward(): encoder → decoder → head"`)
     Do not write or modify code before reading files.
   - **Instruction**: execute the code modifications specified in the Judge decision NEXT_ACTION in `{input_file}`. Do not exceed the modification scope.
   - **Returns**: `"modification complete: {one-line summary of changed files}"` (loaded into orchestrator context)

3. **Commit and push**: commit changes to `{branch_name}`. Include modification rationale (reviewer opinion summary) in commit message. Since this is main repo code modification, **push with `git push`** (per CLAUDE.md rules).

4. **Record**: call scribe agent to record the following in `{record_targets}`:
   - List of modified files and change summary
   - Branch name (`{branch_name}`) — for post-hoc review/rollback
   - Modification rationale (which reviewer's opinion it was based on)
   - Diff summary (key changes)
