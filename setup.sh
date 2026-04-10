#!/bin/bash
set -e

# OpenClaw fresh deploy script
# Usage: ssh root@your-server 'bash -s' < setup.sh

DEPLOY_DIR="/docker/my-openclaw"
CONTAINER="${COMPOSE_PROJECT_NAME:-my-openclaw}-openclaw-1"

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

  # Inject Slack channel ID into heartbeat target
  SLACK_CHANNEL_ID=$(grep SLACK_CHANNEL_ID "$DEPLOY_DIR/.env" | cut -d= -f2)
  if [ -n "$SLACK_CHANNEL_ID" ]; then
    python3 -c "
import json
with open('$DEPLOY_DIR/data/.openclaw/openclaw.json') as f:
    c = json.load(f)
c['agents']['defaults']['heartbeat']['to'] = 'channel:$SLACK_CHANNEL_ID'
with open('$DEPLOY_DIR/data/.openclaw/openclaw.json', 'w') as f:
    json.dump(c, f, indent=2)
"
  fi

  echo "==> Config seeded"
else
  echo "==> Config already exists, skipping"
fi

echo "==> Workspace directory ready at $DEPLOY_DIR/data/.openclaw/workspace/"
echo "    Copy workspace files with: scp workspace/* root@\$(hostname -I | awk '{print \$1}'):$DEPLOY_DIR/data/.openclaw/workspace/"

echo "==> Fixing permissions"
chown -R 1000:1000 "$DEPLOY_DIR/data/"

echo "==> Starting containers"
cd "$DEPLOY_DIR"
docker compose up -d

echo "==> Waiting for gateway..."
sleep 15

echo "==> Approving device"
docker exec "$CONTAINER" openclaw devices approve --latest 2>/dev/null || true

echo "==> Register cron jobs by scp'ing workspace/register-crons.sh and running:"
echo "    docker exec -e SLACK_TARGET=\"channel:\$SLACK_CHANNEL_ID\" $CONTAINER bash /home/node/.openclaw/workspace/register-crons.sh"

echo "==> Done. Restart Traefik if this is first deploy:"
echo "    docker restart traefik-traefik-1"
