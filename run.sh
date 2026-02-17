#!/bin/bash
cd "$(dirname "$0")"

LOG="ralph.log"
MAX=50
i=0

cleanup() {
  echo "Stopped at loop $i/$MAX" | tee -a "$LOG"
  exit 0
}
trap cleanup SIGINT SIGTERM

while [ $i -lt $MAX ]; do
  i=$((i+1))
  echo "=== Loop $i/$MAX - $(date) ===" >> "$LOG"
  claude --dangerously-skip-permissions \
    < PROMPT.md >> "$LOG" 2>&1
  echo "=== Exit code: $? ===" >> "$LOG"
  sleep 5
done
