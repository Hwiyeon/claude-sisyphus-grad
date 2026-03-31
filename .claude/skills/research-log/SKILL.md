---
name: research-log
description: Templates, directory structure, and sync rules for writing research logs and updating README
---

# Research Log Templates & Directory Structure

## Directory Structure
```
research/
├── CLAUDE.md              ← operating rules (auto-loaded each session)
├── README.md              ← research status summary (shown on GitHub)
├── logs/
│   ├── YYYY-MM-DD/        ← daily log folder (current week)
│   │   ├── log.md         ← Deep-Dive research log
│   │   └── *.png/jpg      ← experiment result visualizations
│   └── archive/
│       └── MMDD~MMDD/     ← weekly folder (contains daily folders)
├── summaries/             ← weekly (week-MMDD~MMDD.md) / monthly summaries
├── topics/                ← topic-specific cumulative notes
│   └── <topic>/
│       ├── architecture_<topic>.md  ← current best specification
│       ├── experiment_log.md        ← architecture changelog
│       ├── log.md                   ← module-specific cumulative log
│       └── discussion/              ← in-depth topic discussion docs
└── related_work/          ← related papers/techniques
```

## log.md Writing Structure
```
=============================================================================
[Deep-Dive Research Log]
Context Header: YYYY-MM-DD / main topics
=============================================================================

■ Current Objectives
- Today's discussion goals and specific bottlenecks to resolve

■ The 'Missing' Details (Trials & Failures)
- Ideas discussed but not adopted, with specific rejection reasons
- Excluded variables and technical rationale
- Unresolved questions

■ Confirmed Decisions
- Finalized algorithms, model structures, formulas, parameters, hard constraints

■ Architecture Update (if applicable)
- Changed inputs/outputs, new layers/modules, loss, config, etc.
- ASCII Art architecture diagram

■ Technical Artifacts
- Key formulas (KaTeX: $$...$$ block, $...$ inline)
- Key code snippets

■ Experiment Results (if applicable)
- Training curves, metric trends, visualization results
- Images: saved in same folder, referenced by relative path ![desc](filename.png)

■ Future Directions
- Priority To-Do items to tackle first in tomorrow's session
```

## Module-Specific Topic log.md Format
```
# <module name> — Progress Log

## YYYY-MM-DD
### Topic / one-line summary
- Discussion content, decisions, experiment results
- Rejected ideas and reasons (if any)
- Related metrics, formulas, code snippets

## YYYY-MM-DD
...
```

## README.md Update Rules
- README.md records a research status summary (current topics, recent progress, key decisions, open questions)
- Update README.md when finishing daily log or when important decisions are made

## Sync Command
- Sync to GitHub immediately on every update (`git add -A && git commit && git push`)
