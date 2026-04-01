# Standalone Review Command

Runs the multi-agent review pipeline independently on experiment results.
Can be used standalone outside the `/train` loop; performs a one-time review without ralph-loop integration.

---

## Usage

```
/review results=path/to/experiment_N.json detail=path/to/experiment_N_detail.md [review_cycles=1] [config=...] [script=...]
```

## Arguments

| argument | description | default |
|----------|-------------|---------|
| `results` | path to experiment result JSON file | required |
| `detail` | path to experiment detail MD file | required |
| `review_cycles` | number of G→round2→round3→Judge cycle repetitions | 1 |
| `config` | config file path (passed to reviewers as reference) | optional |
| `script` | training script path (passed to reviewers as reference) | optional |
| `lang` | output language for review output (`ko`, `en`, etc.). The project's CLAUDE.md defines the default | project default |

---

## Procedure

### Step 1: Parse and Validate Arguments

Parse arguments from `$ARGUMENTS`.
- Verify that `results` and `detail` files exist
- Infer metric cache path: `cache/metric_cache.jsonl` in the same session directory as `detail` file
- Print parsed values for user confirmation

### Step 2: Load Review Pipeline Module

Read `.claude/prompts/train-review-pipeline.md` to load review rules.

### Step 3: Run Review

Run multi-agent review per `train-review-pipeline.md` rules:
- **Input mapping**:
  - `experiment_n`: extracted from filename (e.g., `experiment_3.json` → 3)
  - `detail_file`: `detail` argument
  - `results_file`: `results` argument
  - `metric_cache`: inferred path (skip if not found)
  - `review_cycles`: argument value
  - `config`, `script`: argument values (not passed to reviewers if absent)

### Step 4: Output Results

- Output Judge decision directly to user
- No `session_continuation.json` manipulation
- No ralph-loop integration
- Review content is recorded in the `detail` file (handled by the review pipeline scribe)

---

## Notes

- This command operates independently of the `/train` loop
- Use for post-hoc analysis of existing experiment result files
- Even if the review suggests code/config modifications, they are not automatically applied — user decides
