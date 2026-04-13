# Standalone Pre-Analysis Command

Runs a Briefing + multi-agent discussion on the training script and config,
and optionally applies improvements automatically via a Code Modifier.
This is a command that runs the analyze mode of `/train` independently.

---

## Usage

```
/analyze script=train.py config=configs/config.yaml [review_cycles=1] [apply=true] [branch_name=analyze-mod]
```

## Arguments

| argument | description | default |
|----------|-------------|---------|
| `script` | path to the training script to analyze | required |
| `config` | path to the config file to analyze | required |
| `review_cycles` | number of G→round2→round3→Judge cycle repetitions | 1 |
| `apply` | whether to automatically apply the Judge decision's NEXT_ACTION | `true` |
| `branch_name` | branch name to create when modifying code | `analyze-mod` |
<!-- PROJECT_INLINE_START -->
| `lang` | output language for reports and messages (`ko`, `en`, etc.). The project's CLAUDE.md defines the default | project default |
<!-- PROJECT_INLINE_END -->

---

## Procedure

### Step 1: Parse and Validate Arguments

Parse arguments from `$ARGUMENTS`.
- Verify that `script` and `config` files exist
- Print parsed values for user confirmation

### Step 2: Create Output Directory

```
research/logs/{YYYY-MM-DD}/analyze_{HH-MM}/
├── reports/
│   ├── pre_analysis_briefing.md
│   └── pre_review_discussion.md
└── cache/
```

### Step 3: Load Modules

Read the following two files to load rules:
- `.claude/prompts/train-recording-rules.md` (Briefing agent, pre-review discussion format)
- `.claude/prompts/train-review-pipeline.md` (multi-agent review discussion)

### Step 4: Call Briefing Agent

Call Briefing agent per the "Pre-Analysis and Model Improvement" section of `train-recording-rules.md`:
- Input: `eval_results/`, `research/logs/`, `research/README.md`, `{script}`, `{config}`
- Output: `reports/pre_analysis_briefing.md`

### Step 5: Multi-Agent Analysis Discussion

Run multi-agent discussion per `train-review-pipeline.md` rules:
- Discussion content recorded in `reports/pre_review_discussion.md`
- Discussion topics: performance bottlenecks, config vs. structural changes, specific improvements, risks/expected impact

### Step 6: Apply Results (when apply=true)

Apply code/config modifications per the Judge decision's NEXT_ACTION:
- **Create branch**: create `{branch_name}` branch to isolate modification history
- **Call Code Modifier agent**: implement improvements specified in Judge NEXT_ACTION
- **Commit**: commit changes (push requires user confirmation)

### Step 7: Output Results

- Output Judge decision directly to user
- Summary of applied modifications (if apply=true)
- Created branch name (if apply=true)
- No `session_continuation.json` manipulation
- No ralph-loop integration

---

## Notes

- This command operates independently of the `/train` loop
- Running with `apply=false` performs analysis only without code modifications
- Modification results are isolated in a separate branch so user can review diff before merging
- Push is not performed automatically — user pushes manually with `git push`
