**English** | [한국어](customization.ko.md)

# Customization Guide

> Referenced from [README.md](../README.md)

---

## Reviewer Roles

**File**: `.claude/prompts/train-review-pipeline.md`

The default multi-agent review panel has 7 reviewers (A~G). Each brings a different perspective to experiment results:

| ID | Role | Focus |
|---|---|---|
| A | Statistician | Loss curves, overfitting, metric trends |
| B | Algorithmist | Model design, training strategy, architecture |
| C | Data Specialist | Data pipeline, preprocessing, sampling |
| D | Feasibility Assessor | Risk assessment, devil's advocate |
| E | Supplement | Gap filling, strengthen weak arguments |
| F | Mediator | Map consensus/conflicts across reviewers |
| G | Research Innovator | Web search for related papers, fundamental approach changes |

**When to customize**: If your domain has specific needs (e.g., add a "Hardware Efficiency" reviewer for edge deployment, or replace the Data Specialist with a "Simulation Fidelity" reviewer for sim-to-real projects).

Edit the reviewer definitions in the file directly. You can add, remove, or modify roles while keeping the same review flow structure.

---

## Abort Conditions

**File**: `.claude/prompts/train-monitor.md`

Default abort triggers:
- **NaN / Inf** detected in loss
- **val_loss diverges** more than 3x from recent average

**When to customize**: Adjust the divergence multiplier for noisy training regimes, or add domain-specific abort conditions (e.g., "abort if GPU memory exceeds 90%", "abort if FID score exceeds 300").

---

## Convergence Threshold

**File**: `.claude/prompts/train-orchestrator-decisions.md`

The default convergence criterion: "key metric improvement below noise level for 2+ consecutive experiments, AND both config and algorithm modifications have been attempted."

**When to customize**: If your metric is inherently noisy (e.g., RL reward), increase the required consecutive experiments. If your pipeline has expensive experiments, lower the threshold to converge faster.

---

## Discussion Module Table

**File**: `.claude/commands/save-discussion.md`

The `/save-discussion` command uses a keyword-to-module mapping table to route discussion files to the correct directory. The default ships with placeholder modules (`module_a`, `module_b`, `module_c`).

**You must customize this** for your project. Replace the example modules with your actual research modules and their keywords:

```markdown
| Module key | Keywords | discussion path | topic log path |
|------------|----------|-----------------|----------------|
| `encoder` | encoder, backbone, feature extraction | `research/topics/encoder/discussion/` | `research/topics/encoder/log.md` |
| `loss` | loss function, contrastive, triplet | `research/topics/loss_design/discussion/` | `research/topics/loss_design/log.md` |
```

The `meta` row (for workflow/tooling discussions) can be kept as-is.

---

## Permission Mode

**File**: `.claude/settings.local.json`

The `defaultMode` setting controls how Claude Code requests permission for tool use.

| Mode | Behavior | Use case |
|---|---|---|
| `"default"` | Prompts for confirmation on each tool use | Interactive development, manual oversight |
| `"bypassPermissions"` | No confirmation prompts | Fully autonomous `/train` loops |

**Recommendation**: For fully autonomous `/train` loops, set `"defaultMode": "bypassPermissions"`. This allows the orchestrator to run training scripts, modify code, and push branches without manual approval at each step.

**Caution**: `bypassPermissions` grants Claude Code unrestricted shell access within your project. Only enable this in isolated environments (e.g., dedicated training servers) where you trust the pipeline fully. The default ships with `"default"` mode.

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```
