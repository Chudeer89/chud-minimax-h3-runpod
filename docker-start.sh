#!/usr/bin/env bash
set -euo pipefail

BAKED=/opt/comfyui-baked
COMFY=/workspace/runpod-slim/ComfyUI

echo "=========================================="
echo " ChuD MiniMax H3 SEEDHUNTER v2.3.1 One-Click"
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
echo "===== DOWNLOAD / REUSE V2.3.1 MODELS ====="
CHUD_H3_COMFY="$COMFY" CHUD_H3_MANIFEST=/opt/chud-h3/model_sources.tsv python3.12 /opt/chud-h3/download-models.py

echo
echo "===== CREATE COMPATIBILITY ALIASES ====="
mkdir -p "$COMFY/models/loras"
mkdir -p "$COMFY/models/ultralytics"

REALISM_SRC="$COMFY/models/loras/MINIMAX/Skin/h3-realism-people-t2v-i2v-r2v.safetensors"
REALISM_ALIAS="$COMFY/models/loras/h3-realism-people-t2v-i2v-r2v.safetensors"
FACE_SRC="$COMFY/models/ultralytics/bbox/face_yolov8m.pt"
FACE_ALIAS="$COMFY/models/ultralytics/face_yolov8m.pt"

if [ -f "$REALISM_SRC" ]; then
    ln -sfn "$REALISM_SRC" "$REALISM_ALIAS"
    echo "[ALIAS] Realism LoRA -> root loras/"
fi
if [ -f "$FACE_SRC" ]; then
    ln -sfn "$FACE_SRC" "$FACE_ALIAS"
    echo "[ALIAS] face_yolov8m.pt -> models/ultralytics/"
fi

echo
echo "===== MODEL SANITY CHECK ====="
test -s "$REALISM_SRC" || { echo "ERROR: missing Realism LoRA"; exit 1; }
test -s "$FACE_SRC" || { echo "ERROR: missing face_yolov8m.pt"; exit 1; }

echo "Realism LoRA: READY"
echo "Face detector: READY"

echo
echo "===== HAND OFF TO RUNPOD ====="
exec /start.sh
