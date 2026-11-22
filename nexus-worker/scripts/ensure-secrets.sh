#!/usr/bin/env bash
# Creates the Worker's two secrets inside Cloudflare. The values are random, are never printed,
# and never exist in GitHub or in the repository.
#   usage: ensure-secrets.sh staging|production [force]
# Without "force" only missing secrets are created. With "force" both are replaced
# (every installation then has to register again, which the app does by itself).
set -euo pipefail
target="${1:?staging or production}"
force="${2:-}"
env_args=()
if [ "$target" = "staging" ]; then env_args=(--env staging); fi

existing="$(npx wrangler secret list "${env_args[@]}" --format json 2>/dev/null || echo '[]')"
for name in TOKEN_SECRET IP_SALT; do
  if [ "$force" != "force" ] && echo "$existing" | jq -e --arg n "$name" 'map(.name) | index($n)' >/dev/null 2>&1; then
    echo "$name: already set"
  else
    echo "$name: creating (the value is not printed)"
    openssl rand -hex 32 | npx wrangler secret put "$name" "${env_args[@]}" >/dev/null
  fi
done
