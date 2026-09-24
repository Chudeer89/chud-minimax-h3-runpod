#!/usr/bin/env bash
set -euo pipefail

BAKED=/opt/comfyui-baked
COMFY=/workspace/runpod-slim/ComfyUI

echo "=========================================="
echo " ChuD MiniMax H3 One-Click"
echo "=========================================="

echo
echo "===== PREPARE COMFYUI ====="
mkdir -p /workspace/runpod-slim

if [ ! -d "$COMFY" ]; then
    echo "First boot: copying locked ComfyUI..."
    cp -a "$BAKED" "$COMFY"
else
    echo "Existing workspace found: syncing locked code and nodes..."
    rsync -a --delete \
        --exclude 'models/' \
        --exclude 'input/' \
        --exclude 'output/' \
        --exclude 'user/' \
        --exclude '.venv*/' \
        "$BAKED/" "$COMFY/"
fi

echo
echo "===== DOWNLOAD / REUSE MODELS ====="
CHUD_H3_COMFY="$COMFY" \
python3.12 /opt/chud-h3/download-models.py

echo
echo "===== HAND OFF TO RUNPOD ====="
exec /start.sh
