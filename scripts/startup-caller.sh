#!/bin/bash
# Startup script for the Caller Worker VM (TypeScript).
# Reads ENGINE_IP from GCE instance metadata set by Terraform.
set -euo pipefail
exec > /var/log/startup-caller.log 2>&1

echo "[startup-caller] $(date) — starting"

# ── Resolve engine IP from GCE metadata ──────────────────────────────────────
ENGINE_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ENGINE_IP" \
  -H "Metadata-Flavor: Google")
echo "[startup-caller] engine IP = ${ENGINE_IP}"

# ── System packages ───────────────────────────────────────────────────────────
apt-get update -q
apt-get install -y curl

# ── Node.js 20 LTS ───────────────────────────────────────────────────────────
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# ── Caller worker source ──────────────────────────────────────────────────────
mkdir -p /opt/caller-worker/src

cat > /opt/caller-worker/package.json << 'JSON'
{
  "name": "caller-worker",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "start": "node --loader ts-node/esm src/worker.ts"
  },
  "dependencies": {
    "iii-sdk": "0.11.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0"
  }
}
JSON

cat > /opt/caller-worker/tsconfig.json << 'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
JSON

cat > /opt/caller-worker/src/worker.ts << 'TYPESCRIPT'
import { Logger, registerWorker } from 'iii-sdk';

const iii = registerWorker(process.env.III_URL ?? 'ws://localhost:49134');
const logger = new Logger();

iii.registerFunction(
  'inference::get_response',
  async (payload: { messages: Record<string, any> } & Record<string, any>) => {
    logger.info('inference::get_response called', payload);
    const result = await iii.trigger({
      function_id: 'inference::run_inference',
      payload,
    });
    return { ...result };
  },
);

iii.registerFunction(
  'http::run_inference_over_http',
  async (payload: { body: { messages: Record<string, any> } & Record<string, any> }) => {
    const result = await iii.trigger({
      function_id: 'inference::get_response',
      payload: payload.body,
    });
    logger.info('http inference complete');
    return {
      status_code: 200,
      body: { result },
      headers: { 'Content-Type': 'application/json' },
    };
  },
);

iii.registerTrigger({
  type: 'http',
  function_id: 'http::run_inference_over_http',
  config: { api_path: '/v1/chat/completions', http_method: 'POST' },
});

logger.info('Caller worker started — listening for calls');
TYPESCRIPT

cd /opt/caller-worker && npm install

# ── systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/caller-worker.service << SERVICE
[Unit]
Description=Caller Worker (TypeScript)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/caller-worker
ExecStart=/usr/bin/npx tsx src/worker.ts
Restart=always
RestartSec=10
Environment=III_URL=ws://${ENGINE_IP}:49134
Environment=NODE_OPTIONS=--experimental-vm-modules
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable caller-worker
systemctl start caller-worker

echo "[startup-caller] $(date) — done"
