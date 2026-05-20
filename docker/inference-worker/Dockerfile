# syntax=docker/dockerfile:1
# ── Stage 1: install Python deps ──────────────────────────────────────────────
FROM python:3.11-slim AS deps
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Stage 2: bake the model weights into the image ────────────────────────────
# This runs at BUILD time so the 300 MB GGUF file is a cached layer.
# Workers cold-start in ~30 s instead of waiting for a HuggingFace download.
FROM deps AS model
COPY download_model.py .
RUN python download_model.py

# ── Stage 3: lean runtime image ───────────────────────────────────────────────
FROM python:3.11-slim
WORKDIR /app

COPY --from=model /root/.cache/huggingface /root/.cache/huggingface
COPY --from=deps  /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=deps  /usr/local/bin /usr/local/bin

COPY inference_worker.py .

# Prevent any runtime network calls to HuggingFace — model is baked in
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

# III_URL is injected at runtime by the startup script / docker run -e
CMD ["python", "inference_worker.py"]
