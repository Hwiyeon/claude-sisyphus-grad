---
name: weekly-summary
description: Generate weekly summary. Triggered by requests like "weekly summary", "this week's recap", etc.
---

# Weekly Summary Rules

## Generation Condition
- **Only generated when user requests it** (no automatic cron)

## Date Range
- Default: previous Wednesday afternoon ~ this Wednesday morning
- Change to user-specified range if provided

## Procedure
1. Read `research/logs/YYYY-MM-DD/log.md` files for the period and summarize
2. If user requests specific content to be included/highlighted, find it in the logs and reflect it
3. Generate summary as `research/summaries/week-MMDD~MMDD.md`
4. Move daily log folders for the period to `research/logs/archive/MMDD~MMDD/`

## Format
- Formulas in KaTeX-compatible format (to avoid breakage when rendered as HTML)
- Focus on key decisions, experiment results, and architecture changes
