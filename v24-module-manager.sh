#!/usr/bin/env bash
set -euo pipefail

COMFY="${CHUD_H3_COMFY:-/workspace/runpod-slim/ComfyUI}"
PY="$COMFY/.venv-cu128/bin/python"
LOCK="/opt/chud-h3/nodes.v24.optional.lock"
MODULES="${1:-${CHUD_V24_MODULES:-none}}"
CONSTRAINT="/opt/comfyui-runtime-constraints.txt"

has_module() {
    local name="$1"
    [[ ",$MODULES," == *",$name,"* ]] || [[ ",$MODULES," == *",all,"* ]]
}

install_node() {
    local wanted="$1"
    while IFS='|' read -r name repo commit; do
        [ -z "$name" ] && continue
        case "$name" in \#*) continue ;; esac
        [ "$name" = "$wanted" ] || continue
        local dst="$COMFY/custom_nodes/$name"
        echo "[v24] Installing $name @ $commit"
        rm -rf "$dst"
        git clone --filter=blob:none --no-tags "$repo" "$dst"
        git -C "$dst" fetch --no-tags origin "$commit" >/dev/null 2>&1 || true
        git -C "$dst" checkout -f "$commit"
        if [ -f "$dst/requirements.txt" ]; then
            "$PY" -m pip install --no-cache-dir -c "$CONSTRAINT" -r "$dst/requirements.txt"
        fi
        return 0
    done < "$LOCK"
    echo "ERROR: optional node '$wanted' not found in lock"
    return 1
}

if [ "$MODULES" = "none" ] || [ -z "$MODULES" ]; then
    echo "[v24] Optional modules disabled; H3 core only."
    exit 0
fi

BEFORE=$("$PY" -c 'import torch; print(torch.__version__)')
echo "[v24] Comfy Torch before extras: $BEFORE"

AFTER=$("$PY" -c 'import torch; print(torch.__version__)')
echo "[v24] Comfy Torch after extras: $AFTER"
if [ "$BEFORE" != "$AFTER" ]; then
    echo "ERROR: Optional module install changed ComfyUI Torch ($BEFORE -> $AFTER). Aborting."
    exit 2
fi

if has_module tts; then
    echo "[v24] Thai TTS runs in an isolated Python 3.11 sidecar."
    nohup /opt/chud-h3/setup-thai-tts.sh > /workspace/thai-tts-setup.log 2>&1 &
    echo "[v24] Thai TTS setup log: /workspace/thai-tts-setup.log"
fi
