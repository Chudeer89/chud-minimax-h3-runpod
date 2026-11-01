#!/usr/bin/env bash
# Extra Hugging Face files at boot, in every mode of the MV image (started by openjutsu-start.sh):
#   CHUD_EXTRA_HF="repo|path_in_repo|dest_under_models[|revision];repo|path|dest"
# HF_TOKEN is used when set. Files download beside ComfyUI (/workspace/extra-hf) at once, then are copied into
# ComfyUI/models once it is up; LoRAs pass through convert_lora_keys.py so diffusers FLUX.3 LoRAs load in ComfyUI.
set -uo pipefail

COMFY=/workspace/runpod-slim/ComfyUI
RAW=/workspace/extra-hf
LIST="${CHUD_EXTRA_HF:-}"
[ -z "$LIST" ] && { echo "[extra-hf] CHUD_EXTRA_HF empty"; exit 0; }

mkdir -p "$RAW"
MANIFEST="$RAW/manifest.tsv"
: > "$MANIFEST"
IFS=';' read -r -a ENTRIES <<< "$LIST"
for entry in "${ENTRIES[@]}"; do
    entry="${entry// /}"
    [ -z "$entry" ] && continue
    IFS='|' read -r repo path dest rev <<< "$entry"
    if [ -z "${repo:-}" ] || [ -z "${path:-}" ] || [ -z "${dest:-}" ]; then
        echo "[extra-hf] skipping bad entry: $entry"
        continue
    fi
    echo "hf|$repo|$path|$dest|${rev:-}" >> "$MANIFEST"
done

echo "[extra-hf] downloading $(wc -l < "$MANIFEST") file(s)"
CHUD_H3_COMFY="$RAW" CHUD_H3_STAGE=/workspace/h3-stage-extra CHUD_H3_MANIFEST="$MANIFEST" \
    python3.12 /opt/chud-h3/download-models.py || echo "[extra-hf] WARNING: some downloads failed"

until curl -fs -o /dev/null -m 5 http://127.0.0.1:8188/system_stats; do sleep 10; done
while IFS='|' read -r _ _ _ dest _; do
    src="$RAW/models/$dest"
    [ -s "$src" ] || { echo "[extra-hf] missing $dest"; continue; }
    mkdir -p "$(dirname "$COMFY/models/$dest")"
    case "$dest" in
        loras/*.safetensors) python3.12 /opt/chud-h3/convert_lora_keys.py "$src" "$COMFY/models/$dest" ;;
        *) cp -f "$src" "$COMFY/models/$dest" && echo "[extra-hf] copied $dest" ;;
    esac
done < "$MANIFEST"
echo "[extra-hf] done"
