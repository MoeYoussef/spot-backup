#!/bin/bash
# Check Spot, Bubble, and Realtor are using Claude CLI subscription

BOT_TOKEN="8121338922:AAHRT4n6QRGZOeas4XyHX4sw2ec3lkGtxWk"
CHAT_ID="6824992387"
ISSUES=""

declare -A AGENTS
AGENTS[Spot]="13b3665ed192"
AGENTS[Bubble]="049a844fd5e3"
AGENTS[Realtor]="cc035e2011b9"

for NAME in "${!AGENTS[@]}"; do
  CID="${AGENTS[$NAME]}"

  if ! docker exec $CID test -f /data/.claude/.credentials.json 2>/dev/null; then
    ISSUES="${ISSUES}\n${NAME}: credentials file missing"
  fi

  MODEL=$(docker exec $CID python3 -c "import json; print(json.load(open('/data/.openclaw/openclaw.json'))['agents']['defaults']['model']['primary'])" 2>/dev/null)
  if [[ "$MODEL" != claude-cli/* ]]; then
    ISSUES="${ISSUES}\n${NAME}: primary model is ${MODEL} (not claude-cli/*)"
  fi

  CLI_TEST=$(docker exec $CID bash -c 'echo "hi" | /data/.npm-global/bin/claude --print 2>&1 | head -1')
  if [ -z "$CLI_TEST" ] || echo "$CLI_TEST" | grep -qi "error"; then
    ISSUES="${ISSUES}\n${NAME}: Claude CLI test failed: ${CLI_TEST}"
  fi
done

if [ -n "$ISSUES" ]; then
  MSG=$(printf "Claude CLI Health Check Failed:%b" "$ISSUES")
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${MSG}" > /dev/null 2>&1
fi

echo "$(date): Check complete. Issues: ${ISSUES:-none}"
