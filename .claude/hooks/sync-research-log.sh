#!/bin/bash
# PostToolUse hook: auto git sync when research/ files are modified
# Reads JSON from stdin, checks file_path, then commits & pushes to research repo
# Uses flock to prevent concurrent runs, executes in background to avoid blocking Claude
#
# Config: RESEARCH_DIR can be overridden via CLAUDE.md or environment variable
# Default: research/ directory two levels above this hook file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESEARCH_DIR="${RESEARCH_DIR:-$PROJECT_ROOT/research}"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# Only process files under the research/ path
if [[ -n "$FILE_PATH" ]] && [[ "$FILE_PATH" == *"/research/"* ]]; then
    LOCK="/tmp/.sisyphus-research-sync.lock"
    (
        flock -n 200 || exit 0  # skip if another sync is already running
        cd "$RESEARCH_DIR" || exit 0
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            git pull --rebase origin main 2>/dev/null || true
            git add -A
            git commit -m "research log sync: $(date +%Y-%m-%d\ %H:%M)" >/dev/null 2>&1
            git push origin main >/dev/null 2>&1
        fi
    ) 200>"$LOCK" &
fi

exit 0
