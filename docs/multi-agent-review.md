**English** | [한국어](multi-agent-review.ko.md)

# Multi-Agent Review Pipeline

> Referenced from [README.md](../README.md)

After each training run, the orchestrator hands off to a structured debate among 7 independent reviewers before any decision is made. No single agent decides — conclusions emerge from argument.

---

## Reviewers

| ID | Role | Focus |
|---|---|---|
| **A** | Statistician | Loss curves, overfitting, metric trends — cites raw numbers directly |
| **B** | Algorithmist | Model design, training strategy, architectural appropriateness |
| **C** | Data Specialist | Data pipeline, preprocessing quality, sampling strategy |
| **D** | Feasibility Assessor | Devil's advocate — evaluates failure scenarios for each proposal, rates risk as `[LOW/MEDIUM/HIGH]` |
| **E** | Supplement | Fills gaps in A/B/C reasoning, strengthens weak arguments |
| **F** | Mediator | Maps consensus and conflicts across A~E — **no judgment, only landscape** |
| **G** | Research Innovator | Web searches for relevant papers, proposes fundamentally different approaches |

Each reviewer receives only **file paths**, not inlined data — they read the experiment files directly and write evidence-based opinions (800 char limit).

---

## Flow

```
[Training ends]
      │
      ▼
  G: Research Brief  ──── WebSearch ────► reports/research_brief_{N}.md
      │
      ▼
  Round 2 ─── Step 1 (parallel): A, B, C  ← receive G's brief as reference
           └── Step 2 (parallel): D, E     ← evaluate A/B/C proposals
           └── Step 3 (sequential): F      ← maps the landscape
      │
      ▼
  Round 3 (parallel): A, B, C update positions after seeing D/E/F
      │
      ▼
  Judge  ──── reads all files ────► DECISION + RATIONALE + NEXT_ACTION
      │
      ▼
  Orchestrator executes
```

The full cycle (`G brief → Round 2 → Round 3 → Judge`) can be repeated N times via `review_cycles` parameter.

---

## G: Research Innovator

G runs before the main debate and operates independently from it.

**What G does:**
- Identifies the core bottleneck in the current experiment
- Runs `WebSearch` to find relevant papers and methods
- Writes `reports/research_brief_{N}.md` (≤1500 chars) with this structure:

```markdown
# Research Brief — Experiment {N}
## Core Problem
[1-2 root bottlenecks identified from results]
## Related Work
### Method 1: [name] ([paper URL])
- Key idea: ...
- Application to our problem: ...
- Why this differs from prior failures: ...
### Method 2: ...
## Implementation Difficulty & Expected Impact
[complexity and expected gain per method]
```

**Key rules:**
- G proposes **fundamental changes** (loss function replacement, architecture paradigm shift, training strategy overhaul) — not config tweaks
- G never withdraws proposals and doesn't participate in the debate rounds
- A/B/C receive G's brief as a reference but judge independently

---

## Round 2

**Step 1 — parallel:** A, B, C each write an independent opinion, with G's research brief available as context.

**Step 2 — parallel:** D and E run after A/B/C.
- D assigns `[LOW/MEDIUM/HIGH]` risk to each A/B/C proposal. For `HIGH`, D must specify the condition under which the proposal would be worth attempting.
- E fills in reasoning gaps and strengthens weaker arguments from A/B/C.

**Step 3 — sequential:** F summarizes the full landscape — where A/B/C/D/E agree, where they conflict, what remains unresolved. F does not take a position.

---

## Round 3

A, B, C each update their positions after seeing D/E/F. If changing stance, they must state why. Positions can be maintained or revised.

---

## Judge

The Judge runs in a **fresh context** — it does not participate in the debate and receives only file paths:

- `reports/experiment_{N}_detail.md` — full review transcript
- `results/experiment_{N}.json` — numeric results
- `cache/metric_cache.jsonl` — per-epoch metrics
- `reports/research_brief_{N}.md` — G's brief

**Output:**
```
DECISION: [go / config_modify / algo_modify / abort]
RATIONALE: [reasoning, ≤200 chars]
NEXT_ACTION: [concrete next step — specific changes if config/algo_modify]
```

**Special rules:**
- G's proposals can be adopted even if A/B/C rejected them — if the evidence is strong
- D's `HIGH`-risk proposals can be adopted if the execution condition is clearly met
- **Evidence quality** takes priority over consensus level

---

## Decision Types

| Decision | Meaning |
|---|---|
| `go` | Current approach has converged sufficiently — stop loop |
| `config_modify` | Adjust hyperparameters, config values; no code changes |
| `algo_modify` | Modify model code, loss function, or data pipeline; creates a new git branch |
| `abort` | Training failed (NaN, divergence); skip to review anyway |

---

## Convergence Principles

**`go` requires ALL of the following:**
1. Core metric improvement over the last 2+ experiments is below noise level
2. Both config modifications AND algorithm modifications have been attempted
3. A majority of reviewers A~F cannot propose further improvements, and G's brief has no viable alternatives

> In other words: `go` after config tuning alone is not allowed. Structural improvements must be attempted first.

**Bold Improvement:**
If config-only adjustments have been tried 2+ consecutive times without meaningful gain, the next decision **must** attempt a structural change (`algo_modify`). The system is biased toward trying bolder changes before declaring convergence.

---

## Circuit Breaker

If `circuit_breaker=N` is set and the same decision type appears N consecutive times, the Judge receives a `circuit_breaker_context` flag:

- `config_modify` loop → Judge strongly pushes toward `algo_modify` unless evidence is overwhelming
- `algo_modify` loop → Judge must state exactly which assumption was wrong; output includes `"사용자 검토 권장"` (recommend user review)
