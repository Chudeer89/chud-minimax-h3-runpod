#!/usr/bin/env bash
# MV image entrypoint (Dockerfile.mv-openjutsu).
#   default            Openjutsu services in the background, then the usual v24 start (docker-start.sh, unchanged:
#                      ComfyUI, core/x2/Krea 2 models, RunPod hand-off). CHUD_OPENJUTSU=0 runs the plain MV pod.
#   CHUD_FLUX_ONLY=1   MV stills only: FLUX.3 Klein and nothing else (no H3 core / x2 / Krea 2 / Openjutsu downloads,
#                      no Openjutsu app or proxy). docker-start.sh is skipped because it stops when the H3 core is missing.
set -euo pipefail

# Openjutsu: without it the first partial-file request (seeking the video player) can stall ComfyUI's /view.
export AIOHTTP_NOSENDFILE=1
mkdir -p /workspace

# CHUD_EXTRA_HF="repo|path|dest;..." : extra Hugging Face files (e.g. FLUX.3 LoRAs) in every mode
if [ -n "${CHUD_EXTRA_HF:-}" ]; then
    echo "[extra-hf] download starts now -> /workspace/extra-hf.log"
    nohup /opt/chud-h3/extra-hf.sh > /workspace/extra-hf.log 2>&1 &
fi

if [ "${CHUD_FLUX_ONLY:-0}" = "1" ]; then
    BAKED=/opt/comfyui-baked
    COMFY=/workspace/runpod-slim/ComfyUI
    echo "[flux-only] FLUX.3 Klein download starts now -> /workspace/flux-models.log"
    nohup /opt/chud-h3/flux-download.sh > /workspace/flux-models.log 2>&1 &
    mkdir -p /workspace/runpod-slim
    # same copy as docker-start.sh
    if [ ! -d "$COMFY" ]; then
        echo "[flux-only] first boot: copying ComfyUI to the volume"
        cp -a "$BAKED" "$COMFY"
    else
        rsync -a --delete --exclude 'models/' --exclude 'input/' --exclude 'output/' --exclude 'user/' \
            --exclude '.venv*/' "$BAKED/" "$COMFY/"
    fi
    mkdir -p "$COMFY/input" "$COMFY/user/default/workflows"
    echo "[flux-only] hand off to RunPod"
    exec /start.sh
fi

if [ "${CHUD_OPENJUTSU:-1}" != "0" ]; then
    echo "[openjutsu] services start in the background -> /workspace/openjutsu.log"
    nohup /opt/chud-h3/openjutsu-services.sh > /workspace/openjutsu.log 2>&1 &
fi

exec /opt/chud-h3/docker-start.sh
