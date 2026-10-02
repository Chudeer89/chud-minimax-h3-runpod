#!/usr/bin/env bash
set -euo pipefail

BAKED=/opt/comfyui-baked
COMFY=/workspace/runpod-slim/ComfyUI

echo "=========================================="
echo " ChuD MiniMax H3 SEEDHUNTER v2.2 One-Click"
echo "=========================================="

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

mkdir -p "$COMFY/user/default/workflows"
cp -f /opt/chud-h3/workflows/minimaxH3SEEDHUNTERLatent_v21.json "$COMFY/user/default/workflows/minimaxH3SEEDHUNTERLatent_v21.json"

echo
echo "===== DOWNLOAD / REUSE V2.2 MODELS ====="
CHUD_H3_COMFY="$COMFY" CHUD_H3_MANIFEST=/opt/chud-h3/model_sources.tsv python3.12 /opt/chud-h3/download-models.py

echo
echo "===== HAND OFF TO RUNPOD ====="
exec /start.sh
