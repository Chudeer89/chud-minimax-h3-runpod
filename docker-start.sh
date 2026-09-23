#!/usr/bin/env bash
set -e

COMFY=/workspace/runpod-slim/ComfyUI
PY="$COMFY/.venv-cu128/bin/python"

echo "=========================================="
echo " ChuD MiniMax H3 One-Click"
echo "=========================================="

echo
echo "===== GPU ====="

"$PY" - <<'PY'
import torch
print("Torch:", torch.__version__)
print("CUDA:", torch.version.cuda)
print("GPU:", torch.cuda.get_device_name(0))
print("Capability:", torch.cuda.get_device_capability(0))
PY

echo
echo "===== SAGE ====="

"$PY" - <<'PY'
try:
    from sageattention.core import get_cuda_arch_versions
    print("SageAttention:", get_cuda_arch_versions())
except Exception as e:
    print("SageAttention ERROR:", e)
    raise
PY

echo
echo "===== MODELS ====="

CHUD_H3_COMFY="$COMFY" \
"$PY" /opt/chud-h3/download-models.py

echo
echo "===== START COMFYUI ====="

cd "$COMFY"

exec "$PY" main.py \
  --listen 0.0.0.0 \
  --port 8188 \
  --enable-cors-header
