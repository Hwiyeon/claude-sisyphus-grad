# /discuss — Research Discussion Mode

Loads research logs and architecture documents into context and starts a research discussion.

## Usage
```
/discuss                    # discussion based on overall research status
/discuss <topic>            # in-depth discussion on a specific topic
/discuss <topic> lang=en    # discussion in a specific language
/discuss $ARGUMENTS         # free topic
```

| argument | description | default |
|----------|-------------|---------|
| `topic` | discussion topic (positional) | optional |
| `lang` | output language (`ko`, `en`, etc.). The project's CLAUDE.md defines the default | project default |

## Procedure

Perform the steps below in order.

### Step 1: Check and Build Context Cache

Check the `research/chat/.context_cache/manifest.json` file:
- **If file doesn't exist**: run `python research/chat/build_context.py` (if the script exists)
- **If file exists**: check if `built_at` field is within 1 hour
  - If older than 1 hour: run `python research/chat/build_context.py`
  - If within 1 hour: use existing cache
- **If script doesn't exist**: directly Read `research/README.md` and recent `research/logs/` files

### Step 2: Load Context

Read the following files:
1. `research/chat/.context_cache/context_summary.md` (if exists) — research summary context
2. `research/CLAUDE.md` (if exists) — research notes operating rules
3. `.claude/prompts/discuss-system.md` — discussion mode behavior rules

If context_summary.md doesn't exist:
- `research/README.md` — research status summary
- 2-3 most recent daily `research/logs/` log.md files

### Step 3: Additional Topic-Specific Load (optional)

Based on `$ARGUMENTS`, Read relevant documents from `research/topics/<topic>/` folder:
- architecture files, experiment_log files, log.md, etc.
- If no argument, start discussion based on overall status without additional loading

### Step 4: Start Discussion

If `lang` is specified, prepend the following directive before starting:
> **Output language**: {resolved language}. Technical terms: keep in original language.

Start the discussion based on loaded context:

- **If topic provided**: summarize the current state of that topic and present open questions or discussion points
- **If no topic**: briefly summarize overall research status and present recent progress and next steps

During discussion:
- If details are needed, point to original file paths and suggest Reading
- Code files (models/, configs/, etc.) may also be freely referenced
- If user includes think/ultrathink keywords, switch to extended thinking mode for deep analysis
