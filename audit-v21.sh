#!/usr/bin/env bash
set -euo pipefail
COMFY="${CHUD_H3_COMFY:-/workspace/runpod-slim/ComfyUI}"
PY="${CHUD_H3_PYTHON:-$COMFY/.venv-cu128/bin/python}"
PORT="${CHUD_H3_PORT:-8188}"

"$PY" - <<PY
import json, urllib.request
url = "http://127.0.0.1:${PORT}/object_info"
with urllib.request.urlopen(url, timeout=10) as r:
    data = json.load(r)
checks = [
    "PixaromaGroupSwitch",
    "MiniMaxH3MediaLoader",
    "MiniMaxH3ReferenceSplitter",
    "MiniMaxH3RefModsLoader",
    "H3PromptIDE",
    "RIFEInterpolation",
    "ImpactSwitch",
    "Anything Everywhere",
    "Power Lora Loader (rgthree)",
    "VHS_VideoCombine",
    "BlockSparseAttention",
    "MiniMaxH3ReferenceToVideo",
]
missing=[]
for n in checks:
    ok=n in data
    print(("OK   " if ok else "MISS ")+n)
    if not ok: missing.append(n)
raise SystemExit(1 if missing else 0)
PY
