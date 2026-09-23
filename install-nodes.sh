#!/usr/bin/env bash
set -euo pipefail

COMFY=/workspace/runpod-slim/ComfyUI
LOCK=/opt/chud-h3/nodes.lock

echo "===== ChuD H3: install locked custom nodes ====="

while IFS='|' read -r name repo commit; do
    [ -z "$name" ] && continue

    if [ "$name" = "ComfyUI" ]; then
        echo "ComfyUI -> $commit"
        git -C "$COMFY" fetch origin
        git -C "$COMFY" checkout -f "$commit"
        continue
    fi

    dst="$COMFY/custom_nodes/$name"

    echo
    echo "NODE: $name"
    echo "REPO: $repo"
    echo "COMMIT: $commit"

    rm -rf "$dst"
    git clone "$repo" "$dst"
    git -C "$dst" checkout -f "$commit"

done < "$LOCK"

echo
echo "===== install requirements ====="

PY="$COMFY/.venv-cu128/bin/python"

for d in "$COMFY"/custom_nodes/*; do
    if [ -f "$d/requirements.txt" ]; then
        echo "Requirements: $(basename "$d")"
        "$PY" -m pip install --no-cache-dir -r "$d/requirements.txt"
    fi
done

echo "===== custom nodes READY ====="
