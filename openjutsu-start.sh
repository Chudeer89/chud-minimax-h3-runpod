#!/usr/bin/env bash
# MV image entrypoint (Dockerfile.mv-openjutsu): starts the Openjutsu services in the background, then the usual v24 start
# (docker-start.sh, unchanged: ComfyUI, core/x2/Krea 2 models, RunPod hand-off). CHUD_OPENJUTSU=0 runs the plain MV pod.
set -euo pipefail

# Openjutsu: without it the first partial-file request (seeking the video player) can stall ComfyUI's /view.
export AIOHTTP_NOSENDFILE=1

if [ "${CHUD_OPENJUTSU:-1}" != "0" ]; then
    mkdir -p /workspace
    echo "[openjutsu] services start in the background -> /workspace/openjutsu.log"
    nohup /opt/chud-h3/openjutsu-services.sh > /workspace/openjutsu.log 2>&1 &
fi

exec /opt/chud-h3/docker-start.sh
