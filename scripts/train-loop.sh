#!/usr/bin/env bash
# train-loop.sh — External session rotation wrapper for /train
#
# Each iteration spawns a new claude -p process to ensure a fresh context.
#
# Usage:
#   ./scripts/train-loop.sh "script=tools/toy_train.py config=configs/toy_train_config.yaml max_experiments=3 experiment_title=test1"

set -euo pipefail

# Allow spawning claude -p from within a Claude Code session
unset CLAUDECODE 2>/dev/null || true

ARGS="$1"
MAX_RETRIES=3
POLL_INTERVAL=2   # seconds between iterations (claude -p has already exited; just a brief pause before respawn)
STALE_TIMEOUT=600 # 10 minutes without written_at change → failure

# --- Parse experiment_title and date from args ---
experiment_title=""
for pair in $ARGS; do
  key="${pair%%=*}"
  val="${pair#*=}"
  if [[ "$key" == "experiment_title" ]]; then
    experiment_title="$val"
    # Strip surrounding quotes if present
    experiment_title="${experiment_title%\"}"
    experiment_title="${experiment_title#\"}"
  fi
done

if [[ -z "$experiment_title" ]]; then
  echo "ERROR: experiment_title is required in arguments"
  exit 1
fi

TODAY=$(date +%Y-%m-%d)
SESSION_DIR="research/logs/${TODAY}/${experiment_title}"
STATE_FILE="${SESSION_DIR}/cache/session_continuation.json"
LOG_DIR="${SESSION_DIR}/cache"
LOG_FILE="${LOG_DIR}/loop.log"

mkdir -p "$LOG_DIR"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

get_status() {
  if [[ -f "$STATE_FILE" ]]; then
    jq -r '.status // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown"
  else
    echo "missing"
  fi
}

get_written_at() {
  if [[ -f "$STATE_FILE" ]]; then
    jq -r '.written_at // ""' "$STATE_FILE" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# --- Main loop ---
consecutive_failures=0
iteration=0

log "=== train-loop.sh started ==="
log "Args: $ARGS"
log "State file: $STATE_FILE"

while true; do
  iteration=$((iteration + 1))
  log "--- Iteration $iteration ---"

  # Build the prompt for claude -p
  # NOTE: Do NOT use "/train" here — that's the launcher command which would
  # recursively spawn another train-loop.sh. Instead, embed the orchestrator
  # prompt directly so the session has full instructions without needing /train.
  ORCHESTRATOR_FILE=".claude/prompts/train-orchestrator.md"
  if [[ ! -f "$ORCHESTRATOR_FILE" ]]; then
    log "ERROR: Orchestrator file not found: $ORCHESTRATOR_FILE"
    exit 1
  fi
  ORCHESTRATOR_CONTENT=$(cat "$ORCHESTRATOR_FILE")
  PROMPT="${ORCHESTRATOR_CONTENT}

---

## 세션 시작 정보

State 파일 경로: ${STATE_FILE}
인자: ${ARGS}
"

  log "Spawning new claude session..."
  log "State file: $STATE_FILE"

  # Record written_at before spawning
  pre_written_at=$(get_written_at)

  # Run claude -p in foreground; capture exit code
  set +e
  claude -p --dangerously-skip-permissions "$PROMPT" >> "$LOG_FILE" 2>&1
  exit_code=$?
  set -e

  log "Claude session exited with code $exit_code"

  # Check state file
  status=$(get_status)
  post_written_at=$(get_written_at)
  log "Status: $status | written_at: $post_written_at"

  case "$status" in
    completed|stopped)
      log "Loop finished: status=$status"
      log "=== train-loop.sh completed ==="
      exit 0
      ;;
    pending_resume|analyzed)
      # Check if session actually made progress
      if [[ "$post_written_at" != "$pre_written_at" ]]; then
        consecutive_failures=0
        log "Progress detected, continuing to next iteration..."
      else
        consecutive_failures=$((consecutive_failures + 1))
        log "WARNING: No progress detected (written_at unchanged). Consecutive failures: $consecutive_failures/$MAX_RETRIES"
        if [[ $consecutive_failures -ge $MAX_RETRIES ]]; then
          log "ERROR: $MAX_RETRIES consecutive failures. Aborting."
          exit 1
        fi
      fi
      ;;
    initial)
      # Check if mid_experiment_recovery exists — orchestrator treats this as pending_resume
      has_recovery=$(jq -r '.mid_experiment_recovery // empty' "$STATE_FILE" 2>/dev/null)
      if [[ -n "$has_recovery" && "$has_recovery" != "null" ]]; then
        log "Status 'initial' but mid_experiment_recovery exists — treating as pending_resume"
        consecutive_failures=0
      else
        consecutive_failures=$((consecutive_failures + 1))
        log "WARNING: Status still 'initial' after session. Consecutive failures: $consecutive_failures/$MAX_RETRIES"
        if [[ $consecutive_failures -ge $MAX_RETRIES ]]; then
          log "ERROR: $MAX_RETRIES consecutive failures. Aborting."
          exit 1
        fi
      fi
      ;;
    *)
      consecutive_failures=$((consecutive_failures + 1))
      log "WARNING: Unexpected status '$status'. Consecutive failures: $consecutive_failures/$MAX_RETRIES"
      if [[ $consecutive_failures -ge $MAX_RETRIES ]]; then
        log "ERROR: $MAX_RETRIES consecutive failures. Aborting."
        exit 1
      fi
      ;;
  esac

  log "Sleeping ${POLL_INTERVAL}s before next iteration..."
  sleep "$POLL_INTERVAL"
done
