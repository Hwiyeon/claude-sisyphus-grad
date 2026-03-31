**English** | [한국어](research-log-rules.ko.md)

# Research Log Writing Rules

Research logs are the shared memory between you and Claude. A log that omits the process is worse than no log — it creates false confidence. These rules exist because the most useful thing in a log is usually what didn't work.

---

## Core principles

### 1. Never skip the process

The log is not a success report. It is a complete record of what was attempted, including dead ends.

If you tried three learning rate values and two failed, all three go in the log with their failure reasons. If you discussed an architecture change and decided against it, that discussion goes in the log.

**Why:** Future sessions — including your own — will re-explore the same ideas if they aren't recorded. Documented failures are blocked search paths; undocumented failures are work that gets repeated.

### 2. Record rejected ideas with reasons

Every idea that was considered and not adopted must appear in **■ The 'Missing' Details** section, with its specific rejection reason.

Good:
> ALiBi considered but rejected — showed +1.2% val_acc on subset but 340ms/batch vs 180ms/batch for RoPE; latency budget exceeded.

Too vague:
> ALiBi didn't seem to work.

**Why:** "We tried this" without "here's why we stopped" is not useful. The reason is the information.

### 3. Cite numbers, not feelings

Every observation about model behavior must be grounded in a specific metric value.

Good:
> val_loss plateaued at 0.43 across epochs 12–18 (Δ < 0.002); learning rate reduction from 1e-3 to 5e-4 had no visible effect.

Not acceptable:
> Loss was high and didn't improve much.

### 4. Write for a future reader with zero context

Assume the next session has no memory of this conversation. The log must contain enough to reconstruct:
- What the current architecture is
- What has been tried and why it was abandoned
- What the open questions are
- What to do next

If a future Claude (or you, three weeks from now) cannot pick up exactly where you left off by reading only the logs, the log is incomplete.

### 5. Compression is the enemy

Don't summarize when detail is available. Don't write "we improved the data pipeline" when you can write what specifically changed, what the before/after metrics were, and why the change was made.

The only exception: ephemeral process details (debugging typos, fixing file paths) don't need to be logged.

---

## Section-by-section rules

### ■ Current Objectives

State the **specific bottleneck** you're addressing today, not a vague goal.

Good:
> Investigate why val_loss diverges after epoch 8 despite train_loss continuing to decrease. Hypothesis: overfitting due to insufficient regularization or data augmentation.

Not useful:
> Continue improving the model.

---

### ■ The 'Missing' Details ← most important section

This section is mandatory and must not be abbreviated. It contains:

- **Rejected ideas** — ideas discussed but not adopted, with specific rejection reasons
- **Excluded variables** — parameters or approaches you explicitly decided not to try, with technical rationale
- **Failed attempts** — things tried that didn't work, with the failure mode described
- **Unresolved questions** — open questions that remain after the session

If this section is empty or has a single bullet, the session was either extremely simple or the log is incomplete.

---

### ■ Confirmed Decisions

Decisions must be specific. Include the actual values, formulas, or hard constraints that were locked in.

Good:
> Fixed: hidden_dim=512, num_heads=8, dropout=0.1. Rationale: sweep over {256, 512, 1024} showed 512 optimal at 87.3% val_acc; 1024 overfit on subset after epoch 5.

Not useful:
> Decided on the model architecture.

---

### ■ Architecture Update

Required whenever any structural change is made. Always includes an ASCII diagram.

```
Before:
Input → Embedding(512) → TransformerEncoder(6L) → CLS → Linear → Output

After:
Input → Embedding(512) → TransformerEncoder(6L) → [CLS, Mean-pool] → Concat → Linear(1024→num_classes) → Output
```

If the architecture didn't change this session, this section can be omitted.

---

### ■ Technical Artifacts

- Formulas: use KaTeX blocks (`$$...$$` for block, `$...$` for inline)
- Code: use fenced code blocks with language tags
- Include only artifacts that are non-obvious or that encode a key decision

---

### ■ Experiment Results

Images go in the **same folder** as the log, referenced with a relative path:

```markdown
![val loss curve](val_loss_epoch.png)
```

Include:
- What the visualization shows
- What the key observation is
- Whether it confirms or contradicts the hypothesis

---

### ■ Future Directions

This section must be **actionable**. It is the starting point for the next session.

Good:
> 1. Test ALiBi with max_position=2048 on subset (skipped today due to time)
> 2. Investigate epoch 8 divergence with gradient norm logging added
> 3. If subset val_acc > 85%, proceed to full dataset run

Not useful:
> Continue experiments. Try more things.

---

## Two-level logging discipline

The research directory uses two levels of logs. Understanding which level to write in is important.

**Daily log** (`logs/YYYY-MM-DD/log.md`):
- Daily index of what happened across all topics
- Cross-topic observations and decisions
- Non-topic-specific experiment results
- A session that touched multiple topics gets a daily entry that points to each topic's detailed log

**Topic log** (`topics/<topic>/log.md`):
- Primary detailed record for that specific module
- ASCII diagrams, formulas, code snippets, full trial history
- The authoritative record for a topic's evolution

**Rule:** Don't duplicate. If something belongs in the topic log, write it there and put a one-line reference in the daily log. If it's cross-topic, put it in the daily log.

---

## Architecture files vs. experiment log

### `architecture_<topic>.md` — current best spec only

This file answers: "What is the current architecture?"

- Contains **only** the current best specification
- **Overwrite on every update** — do not accumulate versions inside this file
- No changelog, no history, no "before/after" comparisons
- As short as needed to fully specify the current state

### `experiment_log.md` — full changelog

This file answers: "How did the architecture evolve?"

Structure:
```
## Architecture v3 (YYYY-MM-DD)
[full spec of v3]

### Algorithm change: added ALiBi (YYYY-MM-DD)
[what changed and why]

#### Config tuning: lr 1e-3 → 5e-4 (YYYY-MM-DD)
[result]
```

Heading levels: `##` for arch versions → `###` for algorithm changes → `####` for config tuning.

---

## `research/README.md` update rules

The README is the research status summary shown on GitHub. It must be kept current.

**Update when:**
- An important decision is confirmed
- The architecture changes
- A topic's direction shifts
- Writing the weekly summary

**Contents:**
- Current research direction and what problem is being solved
- Recent progress (last 1–2 sessions in 2–3 sentences)
- Key decisions (the most important confirmed choices)
- Open questions (the active unknowns driving the next session)

---

## Sync discipline

After any significant log update:
```bash
git add -A && git commit -m "research: YYYY-MM-DD log" && git push
```

Logs that aren't pushed are invisible to future sessions running in different environments.
