#!/usr/bin/env bash
# claude-train-watch — Live-watch training output from a /train background session
#
# Finds the Python training process spawned by train-loop.sh and attaches to its
# stdout via /proc/<pid>/fd/1, so you see real-time tqdm progress as if you ran
# the training command yourself.
#
# Usage:
#   ./scripts/claude-train-watch.sh              # auto-detect training process
#   ./scripts/claude-train-watch.sh <pattern>    # match a specific script name
#
# Tip: add an alias to your .bashrc for quick access:
#   alias claude-train-watch='/path/to/scripts/claude-train-watch.sh'
#
# Press Ctrl+C to stop watching (training continues in the background).

set -euo pipefail

PATTERN="${1:-pretrain\.py|train\.py|finetune\.py}"

# Find all matching PIDs and pick the best one (actual python, not bash wrapper)
resolve_output() {
  local pid="$1"
  local out
  for fd in 1 2; do
    out=$(readlink "/proc/$pid/fd/$fd" 2>/dev/null || true)
    # Skip deleted files, pipes, sockets
    if [[ -n "$out" && -f "$out" ]]; then
      echo "$out"
      return 0
    fi
  done
  return 1
}

best_pid=""
best_out=""

for pid in $(pgrep -f "python.*($PATTERN)" 2>/dev/null || true); do
  # Skip bash wrappers — only want actual python processes
  cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
  if [[ "$cmd" != "python"* ]]; then
    continue
  fi

  out=$(resolve_output "$pid" || true)
  if [[ -n "$out" ]]; then
    best_pid="$pid"
    best_out="$out"
    break
  fi
done

# Fallback: check training_log.txt in checkpoints (training script writes here directly)
if [[ -z "$best_out" ]]; then
  # Find most recent training_log.txt
  log_file=$(find checkpoints/ -name "training_log.txt" -newer /proc/$$/comm 2>/dev/null \
    | head -1 || true)
  if [[ -z "$log_file" ]]; then
    log_file=$(ls -t checkpoints/*/training_log.txt checkpoints/*/*/training_log.txt 2>/dev/null \
      | head -1 || true)
  fi

  if [[ -n "$log_file" && -f "$log_file" ]]; then
    # Get any matching python PID for display
    best_pid=$(pgrep -f "python.*($PATTERN)" 2>/dev/null | head -1 || true)
    best_out="$log_file"
  fi
fi

if [[ -z "$best_pid" && -z "$best_out" ]]; then
  echo "No training process found matching: $PATTERN"
  echo ""
  echo "Currently running python processes:"
  pgrep -af "python" 2>/dev/null || echo "  (none)"
  echo ""
  echo "Usage: $0 [pattern]"
  echo "  e.g. $0 pretrain.py"
  exit 1
fi

full_cmd=$(ps -p "${best_pid:-$$}" -o args= 2>/dev/null || echo "unknown")

echo "=== claude-train-watch ==="
echo "PID:     ${best_pid:-N/A}"
echo "Command: $full_cmd"
echo "Output:  $best_out"
echo "=== Ctrl+C to stop (training continues) ==="
echo ""

tail -f "$best_out"
