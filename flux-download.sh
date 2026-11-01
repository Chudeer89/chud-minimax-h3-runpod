#!/usr/bin/env bash
# Stills models for the MV image, started at boot by openjutsu-start.sh (stills-only pods) or openjutsu-services.sh.
#   CHUD_MODEL_SETS="flux stills" (default "flux")
#     flux    model_sources_openjutsu_flux.tsv  FLUX.3 Klein (gated: needs HF_TOKEN)
#     stills  model_sources_stills_mix.tsv      MOSS Image + CyberRealistic Krea 2 (Civitai: needs CIVITAI_TOKEN)
set -uo pipefail

COMFY=/workspace/runpod-slim/ComfyUI
# ComfyUI is copied onto the volume on first boot, so the files land beside it and are moved in once ComfyUI is up
EARLY=/workspace/flux-early

TSVS=()
for set in ${CHUD_MODEL_SETS:-flux}; do
    case "$set" in
        flux)
            if [ -n "${HF_TOKEN:-}" ]; then
                TSVS+=(/opt/chud-h3/model_sources_openjutsu_flux.tsv)
            else
                echo "[stills] HF_TOKEN not set: FLUX.3 Klein (gated) skipped"
            fi ;;
        stills)
            [ -n "${CIVITAI_TOKEN:-}" ] || echo "[stills] CIVITAI_TOKEN not set: CyberRealistic Krea 2 will fail"
            TSVS+=(/opt/chud-h3/model_sources_stills_mix.tsv) ;;
        *) echo "[stills] unknown model set: $set" ;;
    esac
done
[ "${#TSVS[@]}" = 0 ] && exit 0

for tsv in "${TSVS[@]}"; do
    missing=0
    for dest in $(grep -v '^#' "$tsv" | cut -d'|' -f4); do
        [ -s "$COMFY/models/$dest" ] || missing=1
    done
    if [ "$missing" = 1 ]; then
        echo "[stills] downloading $(basename "$tsv")"
        CHUD_H3_COMFY="$EARLY" CHUD_H3_STAGE=/workspace/h3-stage-flux CHUD_H3_MANIFEST="$tsv" \
            python3.12 /opt/chud-h3/download-models.py || echo "[stills] WARNING: some files of $(basename "$tsv") failed"
    fi
done

until curl -fs -o /dev/null -m 5 http://127.0.0.1:8188/system_stats; do sleep 10; done
for tsv in "${TSVS[@]}"; do
    for dest in $(grep -v '^#' "$tsv" | cut -d'|' -f4); do
        if [ -s "$EARLY/models/$dest" ] && [ ! -s "$COMFY/models/$dest" ]; then
            mkdir -p "$(dirname "$COMFY/models/$dest")"
            mv -f "$EARLY/models/$dest" "$COMFY/models/$dest"
        fi
    done
done
# the official FLUX.3 Klein templates (MV stills) load the Hugging Face file name
KLEIN="$COMFY/models/diffusion_models/flux3_image_klein_sd_int8_convrot.safetensors"
[ -f "$KLEIN" ] && ln -sfn "$KLEIN" "$COMFY/models/diffusion_models/flux3-image-klein-int8-convrot.safetensors"
echo "[stills] model files are in ComfyUI/models"
