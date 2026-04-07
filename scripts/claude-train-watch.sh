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

PATTERN="${1:-pretrain\.py\|train\.py\|finetune\.py}"

# Find the training process
pid=$(pgrep -f "python.*($PATTERN)" 2>/dev/null | head -1 || true)

if [[ -z "$pid" ]]; then
  echo "No training process found matching: $PATTERN"
  echo ""
  echo "Currently running python processes:"
  pgrep -af "python" 2>/dev/null || echo "  (none)"
  echo ""
  echo "Usage: $0 [pattern]"
  echo "  e.g. $0 pretrain.py"
  exit 1
fi

# Resolve the output file from the process's stdout fd
out=$(readlink "/proc/$pid/fd/1" 2>/dev/null || true)

if [[ -z "$out" || ! -f "$out" ]]; then
  # Fallback: try stderr
  out=$(readlink "/proc/$pid/fd/2" 2>/dev/null || true)
fi

if [[ -z "$out" || ! -f "$out" ]]; then
  echo "Could not resolve output file for PID $pid"
  echo "fd/1 -> $(readlink /proc/$pid/fd/1 2>/dev/null || echo 'N/A')"
  echo "fd/2 -> $(readlink /proc/$pid/fd/2 2>/dev/null || echo 'N/A')"
  exit 1
fi

cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")

echo "=== claude-train-watch ==="
echo "PID:     $pid"
echo "Command: $cmd"
echo "Output:  $out"
echo "=== Ctrl+C to stop (training continues) ==="
echo ""

tail -f "$out"
