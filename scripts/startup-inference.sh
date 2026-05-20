#!/bin/bash
# Startup script for the Inference Worker VM (Python + Gemma-3-270M GGUF).
# Reads ENGINE_IP from GCE instance metadata set by Terraform.
set -euo pipefail
exec > /var/log/startup-inference.log 2>&1

echo "[startup-inference] $(date) — starting"

# ── Resolve engine IP from GCE metadata ──────────────────────────────────────
ENGINE_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ENGINE_IP" \
  -H "Metadata-Flavor: Google")
echo "[startup-inference] engine IP = ${ENGINE_IP}"

# ── System packages ───────────────────────────────────────────────────────────
apt-get update -q
apt-get install -y python3 python3-pip python3-venv curl

# ── Python virtual environment ────────────────────────────────────────────────
python3 -m venv /opt/inference-worker/venv

cat > /opt/inference-worker/requirements.txt << 'REQ'
iii-sdk==0.11.0
watchfiles
transformers
torch
gguf
accelerate
REQ

/opt/inference-worker/venv/bin/pip install --upgrade pip --quiet
/opt/inference-worker/venv/bin/pip install -r /opt/inference-worker/requirements.txt --quiet

# ── Inference worker script ───────────────────────────────────────────────────
cat > /opt/inference-worker/inference_worker.py << 'PYTHON'
import os
from typing import Any, Dict, List

from iii import InitOptions, Logger, register_worker
from transformers import AutoModelForCausalLM, AutoTokenizer

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="inference-worker"),
)
logger = Logger()

model_id   = "ggml-org/gemma-3-270m-GGUF"
gguf_file  = "gemma-3-270m-Q8_0.gguf"

logger.info(f"Loading model {model_id} ...")
tokenizer = AutoTokenizer.from_pretrained(model_id, gguf_file=gguf_file)
model     = AutoModelForCausalLM.from_pretrained(model_id, gguf_file=gguf_file)
logger.info("Model loaded.")

CHAT_TEMPLATE = (
    "{{ bos_token }}"
    "{%- if messages[0]['role'] == 'system' -%}"
        "{%- if messages[0]['content'] is string -%}"
            "{%- set first_user_prefix = messages[0]['content'] + '\n\n' -%}"
        "{%- else -%}"
            "{%- set first_user_prefix = messages[0]['content'][0]['text'] + '\n\n' -%}"
        "{%- endif -%}"
        "{%- set loop_messages = messages[1:] -%}"
    "{%- else -%}"
        "{%- set first_user_prefix = '' -%}"
        "{%- set loop_messages = messages -%}"
    "{%- endif -%}"
    "{%- for message in loop_messages -%}"
        "{%- if (message['role'] == 'user') != (loop.index0 % 2 == 0) -%}"
            "{{ raise_exception('Conversation roles must alternate user/assistant/...') }}"
        "{%- endif -%}"
        "{%- if message['role'] == 'assistant' -%}"
            "{%- set role = 'model' -%}"
        "{%- else -%}"
            "{%- set role = message['role'] -%}"
        "{%- endif -%}"
        "{{ '<start_of_turn>' + role + '\n' + (first_user_prefix if loop.first else '') }}"
        "{%- if message['content'] is string -%}"
            "{{ message['content'] | trim }}"
        "{%- elif message['content'] is iterable -%}"
            "{%- for item in message['content'] -%}"
                "{%- if item['type'] == 'image' -%}{{ '<start_of_image>' }}"
                "{%- elif item['type'] == 'text' -%}{{ item['text'] | trim }}"
                "{%- endif -%}"
            "{%- endfor -%}"
        "{%- else -%}"
            "{{ raise_exception('Invalid content type') }}"
        "{%- endif -%}"
        "{{ '<end_of_turn>\n' }}"
    "{%- endfor -%}"
    "{%- if add_generation_prompt -%}{{ '<start_of_turn>model\n' }}{%- endif -%}"
)

tokenizer.chat_template = CHAT_TEMPLATE


def run_inference_handler(payload: Dict[str, Any]) -> str:
    messages = payload.get("messages", [])
    text     = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    inputs   = tokenizer(text, return_tensors="pt").to(model.device)
    output   = model.generate(**inputs, max_new_tokens=64)
    result   = tokenizer.decode(output[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True)
    logger.info(f"Inference complete: {result[:80]}...")
    return {"text": result}


iii.register_function("inference::run_inference", run_inference_handler)
logger.info("Inference worker started — listening for calls")
PYTHON

# ── systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/inference-worker.service << SERVICE
[Unit]
Description=Inference Worker (Python + Gemma-3-270M)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/inference-worker
ExecStart=/opt/inference-worker/venv/bin/python inference_worker.py
Restart=always
RestartSec=15
Environment=III_URL=ws://${ENGINE_IP}:49134
Environment=PATH=/opt/inference-worker/venv/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable inference-worker
systemctl start inference-worker

echo "[startup-inference] $(date) — done (model download may continue in background)"
