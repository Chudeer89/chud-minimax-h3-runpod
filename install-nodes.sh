#!/usr/bin/env bash
set -euo pipefail

COMFY="${CHUD_H3_COMFY:-/opt/comfyui-baked}"
LOCK="${CHUD_H3_LOCK:-/opt/chud-h3/nodes.lock}"
PY="${CHUD_H3_PYTHON:-python3.12}"
CONSTRAINT="${CHUD_H3_CONSTRAINT:-/opt/comfyui-runtime-constraints.txt}"

echo "===== ChuD H3 v2.1: install locked stack ====="
echo "ComfyUI: $COMFY"
echo "Python:  $PY"

if [ ! -d "$COMFY" ]; then
    echo "ERROR: ComfyUI not found at $COMFY"
    exit 1
fi
if [ ! -f "$LOCK" ]; then
    echo "ERROR: lock file not found at $LOCK"
    exit 1
fi

mkdir -p "$COMFY/custom_nodes"

while IFS='|' read -r name repo commit; do
    name="${name%$'\r'}"; repo="${repo%$'\r'}"; commit="${commit%$'\r'}"
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac

    echo
    echo "===== $name ====="
    if [ "$name" = "ComfyUI" ]; then
        if [ -d "$COMFY/.git" ]; then
            git -C "$COMFY" remote set-url origin "$repo" 2>/dev/null || true
            git -C "$COMFY" fetch --all --tags
            git -C "$COMFY" checkout -f "$commit"
        else
            echo "INFO: $COMFY is not a git checkout; keeping baked ComfyUI core."
        fi
        continue
    fi

    dst="$COMFY/custom_nodes/$name"
    rm -rf "$dst"
    git clone --filter=blob:none "$repo" "$dst"
    git -C "$dst" checkout -f "$commit"
done < "$LOCK"

PIP_BASE=("$PY" -m pip install --no-cache-dir)
if [ -f "$CONSTRAINT" ]; then
    PIP_BASE+=( -c "$CONSTRAINT" )
fi

echo
echo "===== INSTALL COMFYUI REQUIREMENTS ====="
if [ -f "$COMFY/requirements.txt" ]; then
    "${PIP_BASE[@]}" -r "$COMFY/requirements.txt"
fi

echo
echo "===== INSTALL CUSTOM NODE REQUIREMENTS ====="
for req in "$COMFY"/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue
    case "$req" in
        *ComfyUI-Impact-Pack/requirements.txt)
            echo "Skipping Impact-Pack requirements.txt (SAM2 build isolation conflicts with locked Torch)."
            ;;
        *)
            echo "Installing: $req"
            "${PIP_BASE[@]}" -r "$req"
            ;;
    esac
done

echo
echo "===== IMPACT PACK SAFE DEPENDENCIES ====="
"${PIP_BASE[@]}" scikit-image segment-anything piexif transformers opencv-python-headless scipy dill matplotlib

echo
echo "===== RIFE MODEL ====="
RIFE_DL="$COMFY/custom_nodes/ComfyUI-VFI/rife/download_rife.py"
RIFE_DIR="$COMFY/custom_nodes/ComfyUI-VFI/rife/train_log"
if [ -f "$RIFE_DL" ]; then
    mkdir -p "$RIFE_DIR"
    "$PY" "$RIFE_DL" "$RIFE_DIR" || echo "WARN: RIFE auto-download failed; it can be retried later."
fi

echo
echo "===== LOCKED NODE STACK READY ====="
