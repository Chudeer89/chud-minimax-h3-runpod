#!/usr/bin/env bash
set -euo pipefail

BAKED=/opt/comfyui-baked
COMFY=/workspace/runpod-slim/ComfyUI

echo "=========================================="
echo " ChuD MiniMax H3 One-Click"
echo "=========================================="

echo
echo "===== PREPARE COMFYUI ====="

if [ ! -d "$COMFY" ]; then
    echo "First boot: copying locked ComfyUI..."
    mkdir -p /workspace/runpod-slim
    cp -a "$BAKED" "$COMFY"
fi

echo
echo "===== DOWNLOAD / REUSE MODELS ====="

CHUD_H3_COMFY="$COMFY" \
python3.12 /opt/chud-h3/download-models.py

echo
echo "===== HAND OFF TO RUNPOD ====="

exec /start.sh
