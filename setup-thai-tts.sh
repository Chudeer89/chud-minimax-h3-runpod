#!/usr/bin/env bash
set -euo pipefail

ROOT="${CHUD_THAI_TTS_ROOT:-/workspace/chud-v24/index-tts-thai}"
SRC="$ROOT/src_repo"
VENV="$ROOT/.venv"
CHECKPOINTS="$ROOT/checkpoints"
LORA_DIR="$ROOT/thai_lora"
UPSTREAM="https://github.com/dubbing-ai/indextts2-thai.git"
UPSTREAM_COMMIT="1a5ef7de72b8a39408581153d45307be29a20c0d"

mkdir -p "$ROOT"

if ! command -v uv >/dev/null 2>&1; then
    echo "[Thai TTS] Installing uv..."
    python3.12 -m pip install --no-cache-dir uv
fi

if [ ! -d "$SRC/.git" ]; then
    echo "[Thai TTS] Cloning pinned Thai TTS source..."
    rm -rf "$SRC"
    git clone --filter=blob:none --no-tags "$UPSTREAM" "$SRC"
fi
git -C "$SRC" fetch --no-tags origin "$UPSTREAM_COMMIT" >/dev/null 2>&1 || true
git -C "$SRC" checkout -f "$UPSTREAM_COMMIT"

if [ ! -x "$VENV/bin/python" ]; then
    echo "[Thai TTS] Creating isolated Python 3.11 environment..."
    uv python install 3.11
    uv venv --python 3.11 "$VENV"
fi

if [ ! -f "$ROOT/.deps-ready" ]; then
    echo "[Thai TTS] Installing isolated dependencies. This does NOT touch ComfyUI Torch."
    uv pip install --python "$VENV/bin/python" -e "$SRC"
    "$VENV/bin/python" -m pip install --no-cache-dir "peft>=0.18.1" "pythainlp>=5.3.1" "sentencepiece>=0.2.1" fastapi "uvicorn[standard]" python-multipart
    touch "$ROOT/.deps-ready"
fi

echo "[Thai TTS] Downloading/reusing IndexTTS2 base + Thai adapter..."
ROOT_ENV="$ROOT" CHECKPOINTS_ENV="$CHECKPOINTS" LORA_ENV="$LORA_DIR" "$VENV/bin/python" - <<'PY'
import os
from huggingface_hub import snapshot_download

token = os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN")
base = os.environ["CHECKPOINTS_ENV"]
lora = os.environ["LORA_ENV"]

snapshot_download(
    repo_id="IndexTeam/IndexTTS-2",
    local_dir=base,
    token=token,
)
snapshot_download(
    repo_id="dubbing-ai/indextts2-thai-lora",
    local_dir=lora,
    token=token,
    allow_patterns=["adapter_model.safetensors","adapter_config.json","extra_weights.pt","bpe_thai.model","README.md","LICENSE*"],
)
print("[Thai TTS] model files READY")
PY

pkill -f "thai_tts_server.py" 2>/dev/null || true
echo "[Thai TTS] Starting sidecar on port 7865..."
CHUD_THAI_TTS_ROOT="$ROOT" \
CHUD_THAI_TTS_SRC="$SRC" \
CHUD_THAI_TTS_CHECKPOINTS="$CHECKPOINTS" \
CHUD_THAI_TTS_LORA="$LORA_DIR" \
CHUD_THAI_TTS_PORT=7865 \
nohup "$VENV/bin/python" /opt/chud-h3/thai_tts_server.py > /workspace/thai-tts.log 2>&1 &

echo "[Thai TTS] setup launched. Log: /workspace/thai-tts.log"
