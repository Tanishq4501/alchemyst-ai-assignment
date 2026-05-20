#!/bin/bash
# Post-deploy smoke test.
# Polls the API until it returns a valid response (or times out).
#
# Usage:
#   ./scripts/smoke-test.sh <public-ip>
#   ./scripts/smoke-test.sh   # auto-reads IP from terraform output
#
# Exit codes:
#   0 — API healthy, result field present
#   1 — timeout or invalid response
set -euo pipefail

PUBLIC_IP="${1:-}"
if [ -z "${PUBLIC_IP}" ]; then
  echo "[smoke-test] Reading IP from terraform output..."
  PUBLIC_IP=$(cd "$(dirname "$0")/../terraform/envs/prod" && terraform output -raw api_gateway_public_ip 2>/dev/null)
fi

if [ -z "${PUBLIC_IP}" ]; then
  echo "[smoke-test] ERROR: no public IP provided and terraform output failed"
  exit 1
fi

ENDPOINT="http://${PUBLIC_IP}/v1/chat/completions"
MAX_WAIT=600      # 10 min — inference-worker needs time to load the model
POLL_INTERVAL=15  # check every 15 s
INFER_TIMEOUT=90  # curl timeout per request

echo "[smoke-test] Polling ${ENDPOINT} (max ${MAX_WAIT}s) ..."

elapsed=0
while [ "${elapsed}" -lt "${MAX_WAIT}" ]; do
  http_code=$(curl -s -o /tmp/smoke_response.json \
    -w "%{http_code}" \
    -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Say OK."}]}' \
    --max-time "${INFER_TIMEOUT}" 2>/dev/null || echo "000")

  if [ "${http_code}" = "200" ]; then
    # Validate the response contains a 'result' key.
    # Priority: jq (most accurate) → grep (most portable, works on Windows Git Bash)
    # python3 is intentionally skipped: native Windows python3 cannot resolve
    # POSIX /tmp paths produced by Git Bash curl -o.
    if command -v jq &>/dev/null; then
      result=$(jq -r '.result // empty' /tmp/smoke_response.json 2>/dev/null)
    else
      result=$(grep -o '"result"' /tmp/smoke_response.json 2>/dev/null || echo "")
    fi

    if [ -n "${result}" ]; then
      echo ""
      echo "[smoke-test] PASS — API returned a valid response after ${elapsed}s"
      echo "[smoke-test] Response: $(cat /tmp/smoke_response.json)"
      exit 0
    fi
  fi

  echo "[smoke-test] Not ready yet (HTTP ${http_code}, ${elapsed}s elapsed) — retrying in ${POLL_INTERVAL}s..."
  sleep "${POLL_INTERVAL}"
  elapsed=$((elapsed + POLL_INTERVAL))
done

echo ""
echo "[smoke-test] FAIL — API did not return expected response within ${MAX_WAIT}s"
echo "[smoke-test] Last HTTP code: ${http_code}"
echo "[smoke-test] Last response: $(cat /tmp/smoke_response.json 2>/dev/null || echo 'none')"
exit 1
