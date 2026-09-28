#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFY="${CHUD_H3_COMFY:-/workspace/runpod-slim/ComfyUI}"
PY="${CHUD_H3_PYTHON:-$COMFY/.venv-cu128/bin/python}"
WORKFLOW_TMP="/tmp/minimaxH3SEEDHUNTERLatent_v21.json"

if [ ! -x "$PY" ]; then
    echo "ERROR: Python venv not found at $PY"
    echo "Start from a RunPod ComfyUI template that provides /workspace/runpod-slim/ComfyUI/.venv-cu128"
    exit 1
fi

export CHUD_H3_COMFY="$COMFY"
export CHUD_H3_PYTHON="$PY"
export CHUD_H3_LOCK="$REPO_DIR/nodes.lock"
export CHUD_H3_MANIFEST="$REPO_DIR/model_sources.tsv"
if [ -f /opt/comfyui-runtime-constraints.txt ]; then
    export CHUD_H3_CONSTRAINT=/opt/comfyui-runtime-constraints.txt
else
    export CHUD_H3_CONSTRAINT=/dev/null
fi

echo "=========================================="
echo " ChuD MiniMax H3 SEEDHUNTER v2.1 Restore"
echo "=========================================="

echo
echo "===== ASSEMBLE V2.1 WORKFLOW ====="
bash "$REPO_DIR/assemble-workflow.sh" "$REPO_DIR/workflows/chunks" "$WORKFLOW_TMP"

echo
echo "===== INSTALL LOCKED NODES ====="
bash "$REPO_DIR/install-nodes.sh"

echo
echo "===== DOWNLOAD / REUSE MODELS ====="
"$PY" -m pip install --no-cache-dir "huggingface-hub>=1.27.0" "hf-xet>=1.6.0"
CHUD_H3_STAGE=/workspace/h3-stage "$PY" "$REPO_DIR/download-models.py"

mkdir -p "$COMFY/user/default/workflows"
cp -f "$WORKFLOW_TMP" "$COMFY/user/default/workflows/minimaxH3SEEDHUNTERLatent_v21.json"

echo
echo "===== TORCH CHECK ====="
"$PY" - <<'PY'
import torch
print("Torch:", torch.__version__)
print("CUDA:", torch.version.cuda)
PY

echo
echo "✅ RESTORE COMPLETE"
echo "Workflow: $COMFY/user/default/workflows/minimaxH3SEEDHUNTERLatent_v21.json"
echo "Start ComfyUI with:"
echo "cd $COMFY && source .venv-cu128/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header"
