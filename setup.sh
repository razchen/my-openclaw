#!/bin/bash
set -e

# OpenClaw fresh deploy script
# Usage: ssh root@your-server 'bash -s' < setup.sh

DEPLOY_DIR="/docker/my-openclaw"

echo "==> Creating directories"
mkdir -p "$DEPLOY_DIR/data/.openclaw/workspace"

echo "==> Seeding config"
if [ ! -f "$DEPLOY_DIR/data/.openclaw/openclaw.json" ]; then
  cp openclaw.seed.json "$DEPLOY_DIR/data/.openclaw/openclaw.json"

  # Inject gateway token from .env
  TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN "$DEPLOY_DIR/.env" | cut -d= -f2)
  if [ -n "$TOKEN" ]; then
    python3 -c "
import json
with open('$DEPLOY_DIR/data/.openclaw/openclaw.json') as f:
    c = json.load(f)
c['gateway']['auth']['token'] = '$TOKEN'
c['gateway']['remote'] = {'token': '$TOKEN'}
with open('$DEPLOY_DIR/data/.openclaw/openclaw.json', 'w') as f:
    json.dump(c, f, indent=2)
"
  fi

  # Inject OpenRouter API key
  OR_KEY=$(grep OPENROUTER_API_KEY "$DEPLOY_DIR/.env" | cut -d= -f2)
  if [ -n "$OR_KEY" ]; then
    python3 -c "
import json
with open('$DEPLOY_DIR/data/.openclaw/openclaw.json') as f:
    c = json.load(f)
c['models']['providers']['openrouter']['apiKey'] = '$OR_KEY'
with open('$DEPLOY_DIR/data/.openclaw/openclaw.json', 'w') as f:
    json.dump(c, f, indent=2)
"
  fi

  echo "==> Config seeded"
else
  echo "==> Config already exists, skipping"
fi

echo "==> Fixing permissions"
chown -R 1000:1000 "$DEPLOY_DIR/data/"

echo "==> Starting containers"
cd "$DEPLOY_DIR"
docker compose up -d

echo "==> Waiting for gateway..."
sleep 15

echo "==> Approving device"
docker exec "${COMPOSE_PROJECT_NAME:-my-openclaw}-openclaw-1" openclaw devices approve --latest 2>/dev/null || true

echo "==> Done. Restart Traefik if this is first deploy:"
echo "    docker restart traefik-traefik-1"
