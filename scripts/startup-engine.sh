#!/bin/bash
# Startup script for the API Gateway VM.
# Runs the iii engine (WebSocket hub on :49134, HTTP API on :3111)
# and nginx as a reverse proxy on port 80.
set -euo pipefail
exec > /var/log/startup-engine.log 2>&1

echo "[startup-engine] $(date) — starting"

# ── System packages ──────────────────────────────────────────────────────────
apt-get update -q
apt-get install -y curl nginx

# ── iii CLI ──────────────────────────────────────────────────────────────────
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

# ── iii project directory ────────────────────────────────────────────────────
mkdir -p /opt/iii-engine/data

cat > /opt/iii-engine/config.yaml << 'YAML'
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii
      exporter: memory
      memory_max_spans: 10000
      metrics_enabled: true
      metrics_exporter: memory
      logs_enabled: true
      logs_exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0

  - name: iii-queue
    config:
      adapter:
        name: builtin

  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /opt/iii-engine/data/state_store.db

  - name: iii-http
    config:
      port: 3111
      host: 0.0.0.0
      default_timeout: 120000
      concurrency_request_limit: 1024
      cors:
        allowed_origins:
          - '*'
        allowed_methods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
YAML

# ── systemd: iii-engine ───────────────────────────────────────────────────────
cat > /etc/systemd/system/iii-engine.service << 'SERVICE'
[Unit]
Description=iii Engine (RPC hub + HTTP API)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii-engine
ExecStart=/root/.local/bin/iii --config /opt/iii-engine/config.yaml
Restart=always
RestartSec=5
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iii-engine
systemctl start iii-engine

# ── nginx reverse proxy ───────────────────────────────────────────────────────
# Forwards public port 80 → iii-http on localhost:3111
cat > /etc/nginx/sites-available/default << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    location / {
        proxy_pass         http://127.0.0.1:3111;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }
}
NGINX

systemctl enable nginx
systemctl restart nginx

echo "[startup-engine] $(date) — done"
