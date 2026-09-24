#!/usr/bin/env bash
set -euo pipefail

COMFY=/opt/comfyui-baked
LOCK=/opt/chud-h3/nodes.lock
PY=python3.12
CONSTRAINT=/opt/comfyui-runtime-constraints.txt

echo "===== ChuD H3: install locked stack ====="
echo "Build-time ComfyUI: $COMFY"

if [ ! -d "$COMFY" ]; then
    echo "ERROR: baked ComfyUI not found at $COMFY"
    exit 1
fi

mkdir -p "$COMFY/custom_nodes"

while IFS='|' read -r name repo commit; do
    name="${name%$'\r'}"
    repo="${repo%$'\r'}"
    commit="${commit%$'\r'}"

    [ -z "$name" ] && continue
    case "$name" in
        \#*) continue ;;
    esac

    echo
    echo "===== $name ====="
    echo "$repo"
    echo "$commit"

    if [ "$name" = "ComfyUI" ]; then
        git -C "$COMFY" remote set-url origin "$repo" 2>/dev/null || true
        git -C "$COMFY" fetch origin
        git -C "$COMFY" checkout -f "$commit"
        continue
    fi

    dst="$COMFY/custom_nodes/$name"
    rm -rf "$dst"
    git clone "$repo" "$dst"
    git -C "$dst" checkout -f "$commit"
done < "$LOCK"

echo
echo "===== INSTALL COMFYUI REQUIREMENTS ====="
if [ -f "$COMFY/requirements.txt" ]; then
    "$PY" -m pip install --no-cache-dir -c "$CONSTRAINT" -r "$COMFY/requirements.txt"
fi

echo
echo "===== INSTALL CUSTOM NODE REQUIREMENTS ====="
for req in "$COMFY"/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue
    echo "Installing: $req"
    "$PY" -m pip install --no-cache-dir -c "$CONSTRAINT" -r "$req"
done

echo
echo "===== LOCKED NODE STACK READY ====="
