#!/usr/bin/env bash
# Background part of openjutsu-start.sh: once ComfyUI answers, fetch the Openjutsu models and keep comfy-api-proxy
# (127.0.0.1:8189) and the Openjutsu app (port 3000) running.
set -uo pipefail

COMFY=/workspace/runpod-slim/ComfyUI
APP=/opt/openjutsu
export PATH=/opt/node22/bin:$PATH
export NEXT_TELEMETRY_DISABLED=1

echo "[openjutsu] waiting for ComfyUI on 127.0.0.1:8188"
until curl -fs -o /dev/null -m 5 http://127.0.0.1:8188/system_stats; do sleep 10; done
echo "[openjutsu] ComfyUI is up"

# Openjutsu loads the DMAD LoRA from the loras root; the core manifest keeps it under MINIMAX/.
DMAD="$COMFY/models/loras/MINIMAX/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors"
[ -f "$DMAD" ] && ln -sfn "$DMAD" "$COMFY/models/loras/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors"

# Fix faces is OFF: InsightFace buffalo_l is licensed for non-commercial research only. An empty buffalo_l folder stops
# InsightFace from downloading it on first use, so a Fix faces job fails instead of fetching the model.
BUFFALO="$COMFY/models/insightface/models/buffalo_l"
if [ -z "$(ls -A "$BUFFALO" 2>/dev/null)" ]; then
    mkdir -p "$BUFFALO"
    echo "Fix faces is disabled on the MV pod: buffalo_l is non-commercial only." > "$BUFFALO/DISABLED.txt"
else
    echo "[openjutsu] WARNING: $BUFFALO already has files (non-commercial licence)"
fi

echo "[openjutsu] background download of the Openjutsu models -> /workspace/openjutsu-models.log"
(
    CHUD_H3_COMFY="$COMFY" CHUD_H3_STAGE=/workspace/h3-stage-openjutsu \
        CHUD_H3_MANIFEST=/opt/chud-h3/model_sources_openjutsu.tsv python3.12 /opt/chud-h3/download-models.py
    if [ -n "${HF_TOKEN:-}" ]; then
        CHUD_H3_COMFY="$COMFY" CHUD_H3_STAGE=/workspace/h3-stage-openjutsu \
            CHUD_H3_MANIFEST=/opt/chud-h3/model_sources_openjutsu_flux.tsv python3.12 /opt/chud-h3/download-models.py
    else
        echo "[openjutsu] HF_TOKEN not set: FLUX.3 Klein (gated) skipped, so From picture / Relight cannot run"
    fi
) > /workspace/openjutsu-models.log 2>&1 &

# The app refuses a network address without a password of 12+ characters; without one it stays inside the pod.
HOST=127.0.0.1
PW="${OPENJUTSU_PASSWORD:-}"
if [ "${#PW}" -ge 12 ]; then
    HOST=0.0.0.0
else
    echo "[openjutsu] OPENJUTSU_PASSWORD not set (12+ chars): the app listens on 127.0.0.1:3000 only"
fi

keep_running() {
    local name="$1"; shift
    while true; do
        echo "[openjutsu] starting $name"
        "$@"
        echo "[openjutsu] $name exited ($?), restarting in 5 s"
        sleep 5
    done
}

keep_running proxy "$APP/.venv-proxy/bin/comfy-api-proxy" run --max-upload-mb 500 &
cd "$APP"
keep_running app /opt/node22/bin/npx next start --hostname "$HOST" --port 3000 &
wait
