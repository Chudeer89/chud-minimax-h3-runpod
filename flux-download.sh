#!/usr/bin/env bash
# FLUX.3 Klein for the MV image (model_sources_openjutsu_flux.tsv), started at boot by openjutsu-start.sh (stills-only
# pods) or openjutsu-services.sh. The repo is gated, so nothing happens without HF_TOKEN.
set -uo pipefail

COMFY=/workspace/runpod-slim/ComfyUI
FLUX_TSV=/opt/chud-h3/model_sources_openjutsu_flux.tsv
# ComfyUI is copied onto the volume on first boot, so FLUX lands beside it and is moved in once ComfyUI is up
EARLY=/workspace/flux-early

if [ -z "${HF_TOKEN:-}" ]; then
    echo "[flux] HF_TOKEN not set: FLUX.3 Klein (gated) skipped"
    exit 0
fi

missing=0
for dest in $(grep -v '^#' "$FLUX_TSV" | cut -d'|' -f4); do
    [ -s "$COMFY/models/$dest" ] || missing=1
done
if [ "$missing" = 1 ]; then
    echo "[flux] downloading FLUX.3 Klein now"
    CHUD_H3_COMFY="$EARLY" CHUD_H3_STAGE=/workspace/h3-stage-flux CHUD_H3_MANIFEST="$FLUX_TSV" \
        python3.12 /opt/chud-h3/download-models.py
fi

until curl -fs -o /dev/null -m 5 http://127.0.0.1:8188/system_stats; do sleep 10; done
for dest in $(grep -v '^#' "$FLUX_TSV" | cut -d'|' -f4); do
    if [ -s "$EARLY/models/$dest" ] && [ ! -s "$COMFY/models/$dest" ]; then
        mkdir -p "$(dirname "$COMFY/models/$dest")"
        mv -f "$EARLY/models/$dest" "$COMFY/models/$dest"
    fi
done
# the official FLUX.3 Klein templates (MV stills) load the Hugging Face file name
KLEIN="$COMFY/models/diffusion_models/flux3_image_klein_sd_int8_convrot.safetensors"
[ -f "$KLEIN" ] && ln -sfn "$KLEIN" "$COMFY/models/diffusion_models/flux3-image-klein-int8-convrot.safetensors"
echo "[flux] FLUX.3 Klein files are in ComfyUI/models"
