#!/usr/bin/env bash
set -euo pipefail

BAKED=/opt/comfyui-baked
COMFY=/workspace/runpod-slim/ComfyUI

echo "=========================================="
echo " ChuD MiniMax H3 Studio v2.4 Modular"
echo " Seed Hunter v2.5 core + Thai TTS"
echo "=========================================="

# cp -a prints nothing for minutes on a new volume; report progress every 10 s.
copy_with_progress() {
    local src="$1" dst="$2" total cur pid
    total=$(du -sb "$src" | cut -f1)
    cp -a "$src" "$dst" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        sleep 10
        cur=$(du -sb "$dst" 2>/dev/null | cut -f1 || echo 0)
        awk -v c="${cur:-0}" -v t="$total" 'BEGIN { printf "[COPY %5.1f%%] %.1f / %.1f GiB\n", (t ? 100*c/t : 0), c/1073741824, t/1073741824 }'
    done
    wait "$pid"
    echo "[COPY 100.0%] ComfyUI ready on the volume"
}

mkdir -p /workspace/runpod-slim
if [ ! -d "$COMFY" ]; then
    echo "First boot: copying locked ComfyUI..."
    copy_with_progress "$BAKED" "$COMFY"
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

# Qwen Image 2.1 character-sheet workflows + the mannequin layout template
cp -f /opt/chud-h3/workflows/extra/*.json "$COMFY/user/default/workflows/"
mkdir -p "$COMFY/input"
cp -f /opt/chud-h3/workflows/extra/chud_qwen_sheet_template.png "$COMFY/input/"
echo "[v24] Qwen character-sheet workflows installed."

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

# Workflows saved on Windows store LoRA names like "MINIMAX\file.safetensors".
# On Linux ComfyUI treats that as one literal filename, so the LoRA is silently
# skipped. Expose every LoRA in a subfolder under its backslash name as well.
LORAS="$COMFY/models/loras"
find "$LORAS" -maxdepth 1 -xtype l -name '*\\*' -delete 2>/dev/null || true
BS_COUNT=0
while IFS= read -r -d '' f; do
    rel="${f#"$LORAS"/}"
    case "$rel" in */*) ;; *) continue ;; esac
    ln -sfn "$f" "$LORAS/${rel//\//\\}"
    BS_COUNT=$((BS_COUNT + 1))
done < <(find "$LORAS" -mindepth 2 -type f -name '*.safetensors' -print0)
echo "[ALIAS] $BS_COUNT LoRA(s) -> Windows-style backslash names"

test -s "$REALISM_SRC" || { echo "ERROR: missing Realism LoRA"; exit 1; }
test -s "$FACE_SRC" || { echo "ERROR: missing face_yolov8m.pt"; exit 1; }

echo
echo "===== V2.4 OPTIONAL MODULES ====="
CHUD_H3_COMFY="$COMFY" /opt/chud-h3/v24-module-manager.sh "${CHUD_V24_MODULES:-none}"

if [ -n "${CIVITAI_TOKEN:-}" ]; then
    echo
    echo "===== DOWNLOAD / REUSE CIVITAI MODELS (SparseRef15 Hybrid, Male POV, Frozen World, Motion Combat) ====="
    CHUD_H3_COMFY="$COMFY" CHUD_H3_MANIFEST=/opt/chud-h3/model_sources_civitai.tsv python3.12 /opt/chud-h3/download-models.py         || echo "WARNING: Civitai models not ready; H3 core still works"
else
    echo "[INFO] CIVITAI_TOKEN not set: skipping Civitai models (SparseRef15 Hybrid, Male POV, Frozen World, Motion Combat)"
fi

echo
echo "===== V2.4 READY ====="
echo "Modules: ${CHUD_V24_MODULES:-none}"
echo "Thai TTS endpoint (when enabled): http://127.0.0.1:7865"
echo "ComfyUI Torch remains locked by the v2.3.1 base."

echo
echo "===== HAND OFF TO RUNPOD ====="
exec /start.sh
