#!/bin/bash
# Generic startup script for all worker VMs.
# Reads ENGINE_IP, DOCKER_IMAGE, and CONTAINER_NAME from GCE instance metadata
# (set by Terraform). Installs Docker, authenticates to Artifact Registry,
# pulls the worker image, and runs it as a systemd-managed container.
set -euo pipefail
exec > /var/log/startup-worker.log 2>&1

echo "[startup-worker] $(date) — starting"

# ── Read metadata ─────────────────────────────────────────────────────────────
meta() {
  curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" \
    -H "Metadata-Flavor: Google"
}

ENGINE_IP=$(meta ENGINE_IP)
DOCKER_IMAGE=$(meta DOCKER_IMAGE)
CONTAINER_NAME=$(meta CONTAINER_NAME)

echo "[startup-worker] engine=${ENGINE_IP} image=${DOCKER_IMAGE} name=${CONTAINER_NAME}"

# ── Install Docker ────────────────────────────────────────────────────────────
apt-get update -q
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# ── Authenticate to Artifact Registry via VM service account ─────────────────
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet

# ── Pull image (retry up to 3 times) ─────────────────────────────────────────
for attempt in 1 2 3; do
  docker pull "${DOCKER_IMAGE}" && break
  echo "[startup-worker] pull attempt ${attempt} failed, retrying..."
  sleep 10
done

# ── Run container as a systemd service ───────────────────────────────────────
cat > "/etc/systemd/system/${CONTAINER_NAME}.service" << SERVICE
[Unit]
Description=${CONTAINER_NAME} (Docker)
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/docker stop ${CONTAINER_NAME}
ExecStartPre=-/usr/bin/docker rm   ${CONTAINER_NAME}
ExecStart=/usr/bin/docker run \\
  --name ${CONTAINER_NAME} \\
  --rm \\
  -e III_URL=ws://${ENGINE_IP}:49134 \\
  ${DOCKER_IMAGE}
ExecStop=/usr/bin/docker stop ${CONTAINER_NAME}

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable "${CONTAINER_NAME}"
systemctl start  "${CONTAINER_NAME}"

echo "[startup-worker] $(date) — ${CONTAINER_NAME} started"
