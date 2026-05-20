"""
Runs at Docker BUILD TIME to bake the model weights into the image layer.
This means the inference-worker cold-starts in ~30s instead of downloading
300 MB from HuggingFace on every VM boot.
"""
from transformers import AutoModelForCausalLM, AutoTokenizer

model_id  = "ggml-org/gemma-3-270m-GGUF"
gguf_file = "gemma-3-270m-Q8_0.gguf"

print(f"Downloading {model_id} ({gguf_file}) ...")
AutoTokenizer.from_pretrained(model_id, gguf_file=gguf_file)
AutoModelForCausalLM.from_pretrained(model_id, gguf_file=gguf_file)
print("Model cached successfully — weights are now baked into the image layer.")
