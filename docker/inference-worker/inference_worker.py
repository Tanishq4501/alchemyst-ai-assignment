import os
from typing import Any, Dict

from iii import InitOptions, Logger, register_worker
from transformers import AutoModelForCausalLM, AutoTokenizer

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="inference-worker"),
)
logger = Logger()

MODEL_ID   = "ggml-org/gemma-3-270m-GGUF"
GGUF_FILE  = "gemma-3-270m-Q8_0.gguf"

logger.info(f"Loading model {MODEL_ID} ...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, gguf_file=GGUF_FILE)
model     = AutoModelForCausalLM.from_pretrained(MODEL_ID, gguf_file=GGUF_FILE)
logger.info("Model loaded — ready for inference")

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
                "{%- if item['type'] == 'text' -%}{{ item['text'] | trim }}{%- endif -%}"
            "{%- endfor -%}"
        "{%- else -%}"
            "{{ raise_exception('Invalid content type') }}"
        "{%- endif -%}"
        "{{ '<end_of_turn>\n' }}"
    "{%- endfor -%}"
    "{%- if add_generation_prompt -%}{{ '<start_of_turn>model\n' }}{%- endif -%}"
)

tokenizer.chat_template = CHAT_TEMPLATE


def run_inference_handler(payload: Dict[str, Any]) -> Dict[str, str]:
    messages = payload.get("messages", [])
    text     = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    inputs   = tokenizer(text, return_tensors="pt").to(model.device)
    output   = model.generate(**inputs, max_new_tokens=64)
    result   = tokenizer.decode(output[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True)
    logger.info(f"Inference complete ({len(result)} chars)")
    return {"text": result}


iii.register_function("inference::run_inference", run_inference_handler)
logger.info("Inference worker registered — listening for RPC calls")
