#!/usr/bin/env bash
set -euo pipefail

COMFY=/opt/comfyui-baked
LOCK=/opt/chud-h3/nodes.lock
PY=python3.12
CONSTRAINT=/opt/comfyui-runtime-constraints.txt

echo "===== ChuD H3: install locked stack ====="
echo "Build-time ComfyUI: $COMFY"

while IFS='|' read -r name repo commit; do
    [ -z "$name" ] && continue

    if [ "$name" = "ComfyUI" ]; then
        echo
        echo "===== COMFYUI ====="
        echo "$repo"
        echo "$commit"

        git -C "$COMFY" remote set-url origin "$repo" 2>/dev/null || true
        git -C "$COMFY" fetch origin
        git -C "$COMFY" checkout -f "$commit"
        continue
    fi

    dst="$COMFY/custom_nodes/$name"

    echo
    echo "===== $name ====="
    echo "$repo"
    echo "$commit"

    rm -rf "$dst"
    git clone "$repo" "$dst"
    git -C "$dst" checkout -f "$commit"

done < "$LOCK"

echo
echo "===== INSTALL CUSTOM NODE REQUIREMENTS ====="

for req in "$COMFY"/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue

    echo "Installing: $req"
