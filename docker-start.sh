#!/usr/bin/env bash
set -euo pipefail

BAKED=/opt/comfyui-baked
COMFY=/workspace/runpod-slim/ComfyUI

echo "=========================================="
echo " ChuD MiniMax H3 Studio v2.4 Modular"
echo " Seed Hunter v2.5 core + Thai TTS / LTX / Wan"
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
if [ -f /opt/chud-h3/workflows/minimaxH3SEEDHUNTERLatent_v25.json ]; then
    cp -f /opt/chud-h3/workflows/minimaxH3SEEDHUNTERLatent_v25.json "$COMFY/user/default/workflows/minimaxH3SEEDHUNTERLatent_v25.json"
    echo "[v24] Official Seed Hunter v2.5 workflow installed."
else
    echo "ERROR: Seed Hunter v2.5 workflow was not baked into this image."
    exit 1
fi

echo
echo "===== DOWNLOAD / REUSE H3 CORE MODELS ====="
CHUD_H3_COMFY="$COMFY" CHUD_H3_MANIFEST=/opt/chud-h3/model_sources.tsv python3.12 /opt/chud-h3/download-models.py

echo
echo "===== CREATE H3 COMPATIBILITY ALIASES ====="
mkdir -p "$COMFY/models/loras"
mkdir -p "$COMFY/models/ultralytics"

REALISM_SRC="$COMFY/models/loras/MINIMAX/Skin/h3-realism-people-t2v-i2v-r2v.safetensors"
REALISM_ALIAS="$COMFY/models/loras/h3-realism-people-t2v-i2v-r2v.safetensors"
FACE_SRC="$COMFY/models/ultralytics/bbox/face_yolov8m.pt"
FACE_ALIAS="$COMFY/models/ultralytics/face_yolov8m.pt"
DMAD_SRC="$COMFY/models/loras/MINIMAX/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors"
DMAD_TURBO_ALIAS="$COMFY/models/loras/MINIMAX/Turbo/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors"

if [ -f "$REALISM_SRC" ]; then
    ln -sfn "$REALISM_SRC" "$REALISM_ALIAS"
    echo "[ALIAS] Realism LoRA -> root loras/"
fi
if [ -f "$FACE_SRC" ]; then
    ln -sfn "$FACE_SRC" "$FACE_ALIAS"
    echo "[ALIAS] face_yolov8m.pt -> models/ultralytics/"
fi
if [ -f "$DMAD_SRC" ]; then
    mkdir -p "$COMFY/models/loras/MINIMAX/Turbo"
    ln -sfn "$DMAD_SRC" "$DMAD_TURBO_ALIAS"
    echo "[ALIAS] DMAD 4-step -> MINIMAX/Turbo/"
fi

test -s "$REALISM_SRC" || { echo "ERROR: missing Realism LoRA"; exit 1; }
test -s "$FACE_SRC" || { echo "ERROR: missing face_yolov8m.pt"; exit 1; }

echo
echo "===== V2.4 OPTIONAL MODULES ====="
CHUD_H3_COMFY="$COMFY" /opt/chud-h3/v24-module-manager.sh "${CHUD_V24_MODULES:-none}"

if [ "${CHUD_V24_DOWNLOAD_LTX:-0}" = "1" ]; then
    echo
    echo "===== DOWNLOAD / REUSE LTX-2.5 MODELS ====="
    echo "NOTE: LTX weights may require accepted Hugging Face terms and HF_TOKEN."
    CHUD_H3_COMFY="$COMFY" CHUD_H3_MANIFEST=/opt/chud-h3/model_sources_ltx25.tsv python3.12 /opt/chud-h3/download-models.py
fi

echo
echo "===== V2.4 READY ====="
echo "Modules: ${CHUD_V24_MODULES:-none}"
echo "Thai TTS endpoint (when enabled): http://127.0.0.1:7865"
echo "ComfyUI Torch remains locked by the v2.3.1 base."

echo
echo "===== HAND OFF TO RUNPOD ====="
exec /start.sh
