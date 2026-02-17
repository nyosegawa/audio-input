#!/bin/bash
cd "$(dirname "$0")"

LOG="ralph.log"
LOG_RAW="ralph_raw.log"
MAX=50
i=0

# Read prompt once, safely (avoids shell expansion of backticks)
PROMPT=$(<PROMPT.md)

cleanup() {
  echo "[$(date)] Stopped at loop $i/$MAX" | tee -a "$LOG"
  exit 0
}
trap cleanup SIGINT SIGTERM

while [ $i -lt $MAX ]; do
  i=$((i+1))
  echo "=== Loop $i/$MAX - $(date) ===" | tee -a "$LOG"

  raw=$(claude --dangerously-skip-permissions \
    --output-format json \
    -p "$PROMPT" \
    --continue \
    < /dev/null 2>&1)
  exit_code=$?

  # Save raw JSON
  echo "$raw" >> "$LOG_RAW"

  # Extract clean info
  result=$(echo "$raw" | jq -r '.result // empty' 2>/dev/null)
  cost=$(echo "$raw" | jq -r '.total_cost_usd // empty' 2>/dev/null)
  duration=$(echo "$raw" | jq -r '.duration_ms // empty' 2>/dev/null)
  turns=$(echo "$raw" | jq -r '.num_turns // empty' 2>/dev/null)
  session=$(echo "$raw" | jq -r '.session_id // empty' 2>/dev/null)

  {
    echo "--- Session: $session | Turns: $turns | ${duration}ms | \$$cost | exit:$exit_code ---"
    echo "$result"
    echo ""
  } | tee -a "$LOG"

  sleep 5
done

echo "=== Completed $MAX loops ===" | tee -a "$LOG"
