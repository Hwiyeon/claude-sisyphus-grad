**English** | [한국어](docs/README.ko.md)

# claude-sisyphus-grad

![claude-sisyphus-grad](imgs/sisyphus-grad.png)

> *"One must imagine Sisyphus happy."* — Albert Camus

The grad student your advisor always dreamed of: runs experiments at 3am without complaint, never refuses "just one more ablation," debates results with six colleagues, rewrites the code autonomously, and has clean notes ready before you wake up. Turns out it was Claude Code all along.

Research isn't just "run training, check metric, repeat" — the thinking, the decisions, and the context behind each experiment matter just as much. This project automates the grind without losing that part.

**You do the research. AI does the overnight shifts.**

**Two core features:**
- **Experiment automation** — runs the experiment → review → improve → repeat loop autonomously while you sleep
- **Research notes automation** — structures logs, tracks architecture history, and lets you pick up any thread in seconds

---

## Recent Updates

- **2026-04-20** — Added `/research-state` command for maintaining a `research/state.md` snapshot — a compact "where we are right now" view (~3–5K tokens) sitting between the full `/discuss` cache and the human-readable `README.md`. Uses AUTO/MANUAL section markers (HTML comments) so build-script-generated content (drift warnings, pointers, timestamps) is refreshed automatically while prose sections (current focus + decision tree, recent decisions, rejected paths) are only changed via Claude-proposed edits with user approval. Supports `--export` for generating a self-contained standalone bundle designed to be pasted into external LLMs.
- **2026-04-14** — `/train` monitoring loop now uses background Bash polling + foreground cache-warming pings, reducing orchestrator token consumption by ~70%. Added terse output rules for between-tool-call text.
- **2026-04-13** — Added `<!-- PROJECT_INLINE_START --> / <!-- PROJECT_INLINE_END -->` markers in `.claude/commands/*.md` around sections downstream projects commonly customize (`lang` defaults, module tables, `env` defaults, etc.). The markers are invisible HTML comments and do not affect sisyphus usage. Downstream projects can use them as anchors for sync tooling — pulling generic improvements from upstream while preserving local customizations.

---

## Quick Start

```bash
# 1. Copy to your project
cp -r .claude scripts CLAUDE.md /your/project/
cp -r research-template /your/project/research

# 2. Configure
edit CLAUDE.md   # set CONDA_ENV=your_env_name

# 3. (Optional) Set up research/ as a separate git repo for auto-sync
cd your-project/research && git init && git remote add origin <your-repo-url>

# 4. Run
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

> Full setup guide with file structure: [docs/getting-started.md](docs/getting-started.md)

---

## Experiment Automation

The pipeline automates the **experiment → review → improve → repeat** loop:

1. **`/train`** — launches `scripts/train-loop.sh` in the background; each iteration creates a fresh `claude -p` session
2. **Orchestrator** — manages state via `session_continuation.json`, runs the training script, monitors metrics
3. **Multi-agent review** — 7 reviewers (A~F: statistics, algorithm, data, feasibility, supplement, mediator + G: research innovator with web search) debate the results → [details](docs/multi-agent-review.md)
4. **Judge** — decides: `go` / `config_modify` / `algo_modify` / `abort`
5. **Code Modifier** — if `algo_modify`, creates a git branch, modifies source code autonomously, then restarts
6. **Loop** — continues until `max_experiments` reached or convergence confirmed

The loop runs while you sleep. You wake up to a `session_report.md` and git branches with all code changes for review.

### `/train`

Launches the full automated experiment loop.

```
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

Supports `goal` (natural language target), `instructions` (starting hints), `parallel` runs, and `subset` two-phase strategy.
→ [Full usage examples & arguments table](docs/train-internals.md#usage)

### `/analyze`

Runs a pre-experiment analysis before starting a train loop. Useful for understanding your dataset, baseline behavior, or sanity-checking configs before committing to a long run.

```
/analyze
/analyze target="check class imbalance and feature distributions before training"
```

### `/review`

Runs the multi-agent review pipeline as a standalone command — without starting a new training run. Use this to review an existing experiment result or get a second opinion on results you already have.

```
/review
/review run=results/exp_003 focus="why did val loss diverge at epoch 40?"
```

→ [Review pipeline details](docs/multi-agent-review.md)

### `claude-train-watch`

Live-watch the training output from a running `/train` session — see tqdm progress in real time as if you ran the command yourself.

```bash
# Auto-detect the training process
./scripts/claude-train-watch.sh

# Match a specific script
./scripts/claude-train-watch.sh "my_train.py"

# Optional: add an alias for quick access
alias claude-train-watch='./scripts/claude-train-watch.sh'
```

Works by finding the Python training process and following its stdout via `/proc/<pid>/fd`. Press `Ctrl+C` to stop watching — training continues in the background.

> **Note:** Requires Linux (`/proc` filesystem). Not available on macOS.

---

## Research Notes

A structured research note system. Every experiment run, architecture decision, and discussion thread is logged in a queryable directory — so you can always answer "what did we try last week?" or "what's the current architecture?" in seconds.

### `/discuss`

Loads your research context (logs, architecture docs, experiment history) and starts an interactive research discussion.

```
/discuss                         # overview: full research status
/discuss attention               # deep-dive on the "attention" topic
/discuss "why is val loss noisy" # open-ended question with full context
```

**Example session:**
```
/discuss positional_encoding

> Claude: Based on the experiment log, you've tried 3 variants: RoPE (exp_007), ALiBi
> (exp_012), and learned absolute (exp_003). RoPE gave the best val accuracy (87.3%)
> but showed length generalization issues beyond 512 tokens. ALiBi is still untested
> on the full dataset. Want to dig into the length generalization failure?
```

### `/save-discussion`

Saves the current discussion thread to a structured file under `research/topics/<topic>/discussion/`.

```
/save-discussion
/save-discussion title="positional encoding tradeoffs 2026-03-24"
```

### `/research-state`

Maintains `research/state.md` — a compact "where we are right now" snapshot (~3–5K tokens) for fast re-entry and external LLM sharing. Complements `README.md` (history-oriented) and the full `/discuss` cache (internal index).

```
/research-state           # refresh AUTO sections + propose MANUAL section updates
/research-state --export  # generate state_standalone.md (self-contained bundle for ChatGPT/Gemini)
```

The state file uses HTML comment markers to separate two kinds of sections:
- **AUTO** — regenerated on every run: timestamp header, drift warning (mtime comparison across README and recent logs), canonical file pointers
- **MANUAL** — Claude proposes updates based on recent logs and discussions; user approves each diff per section: current active focus with a decision tree, module metrics, recent confirmed decisions, rejected paths (to avoid re-exploration), top open questions

Typical trigger points: after an experiment result resolves a decision tree branch, before sharing context with an external LLM, or when returning to the project after a break. The `--export` mode inlines pointer files into a single self-contained markdown, useful when you can't rely on the reader having local file access.

### Research directory structure

```
research/
├── CLAUDE.md          ← operating rules
├── README.md          ← research status summary
├── state.md           ← compact "current state" snapshot (optional — created by /research-state)
├── logs/YYYY-MM-DD/   ← daily index logs + visualizations
├── summaries/         ← weekly summaries
├── topics/<topic>/    ← per-topic logs, architecture specs, discussion archives
└── related_work/      ← papers and references
```

→ [File roles & logging rules](docs/research-notes.md) | [Log writing guide](docs/research-log-rules.md)

---

## Customization

Key configuration points — see [full customization guide](docs/customization.md):

- **Reviewer roles** — adapt the 7-reviewer panel to your domain
- **Abort / convergence thresholds** — tune for your metrics
- **Discussion module table** — map `/save-discussion` to your actual research modules
- **Permission mode** — `bypassPermissions` for fully autonomous runs ([details](docs/customization.md#permission-mode))

---

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- `conda` (for environment activation)
- `jq` (for shell JSON parsing)
- `flock` (for hook sync lock, available on Linux; on macOS install via `brew install util-linux`)
- Optional: `wandb` (metric logging — falls back to stdout parsing if unavailable)

---

## Note

This project is under active development. Features and APIs may change without notice.
