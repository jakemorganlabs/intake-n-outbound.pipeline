#!/usr/bin/env bash
set -euo pipefail

# secret_gate.sh: blocks commit if any tracked or staged file contains a secret-like string.
# Exit 0 = clean; exit 1 = blocked.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

MATCH_FOUND=0

# Also fail if .env.production is tracked
if git ls-files | grep -qxF 'deploy/.env.production'; then
  echo "FAIL: deploy/.env.production is tracked in git. Remove it immediately."
  exit 1
fi

# Scan function: grep for pattern, exclude known safe files/hosts
scan() {
  local label="$1"
  local pat="$2"
  local result
  result=$(git grep --no-color -E -I "$pat" 2>/dev/null \
    | grep -v '\.example' \
    | grep -v 'docs/' \
    | grep -v 'scripts/secret_gate.sh' \
    | grep -v 'scripts/setup-vps.sh' \
    | grep -v '\.html:' \
    | grep -vE 'localhost|127\.0\.0\.1' \
    | grep -vE 'postgres:postgres' \
    || true)
  if [ -n "$result" ]; then
    echo "FAIL: found match for: $label"
    echo "$result"
    MATCH_FOUND=1
  fi
}

scan 'sk-ant (Anthropic token)' 'sk-ant'
scan 'sk-* generic key'         'sk-[A-Za-z0-9]{20,}'
scan 'di-* DeepInfra token'     'di-[A-Za-z0-9]{20,}'
scan 'ghp_* GitHub PAT'         'ghp_[A-Za-z0-9]{36}'
scan 'github_pat_* token'       'github_pat_[A-Za-z0-9]{22,}'
scan 'npm_* token'              'npm_[A-Za-z0-9]{36}'
scan 'AKIA* AWS key'            'AKIA[0-9A-Z]{16}'
scan 'TUNNEL_TOKEN=ey'          'TUNNEL_TOKEN=ey'

# Real Slack webhook URLs, not the T000/B000 placeholder
slack_result=$(git grep --no-color -E -I 'hooks\.slack\.com/services/[A-Z0-9]+/[A-Z0-9]+/[a-zA-Z0-9]+' 2>/dev/null \
    | grep -v '\.example' \
    | grep -v 'docs/' \
    | grep -v 'scripts/setup-vps.sh' \
    | grep -v '\.html:' \
    || true)

# Filter out the placeholder pattern T000/B000/XXXX
slack_real=$(echo "$slack_result" | grep -v 'T000/B000/XXXX' || true)

if [ -n "$slack_real" ]; then
  echo "FAIL: found match for: Slack webhook URL"
  echo "$slack_real"
  MATCH_FOUND=1
fi

if [ "$MATCH_FOUND" -eq 1 ]; then
  exit 1
fi

echo "PASS: secret_gate clean."
exit 0
