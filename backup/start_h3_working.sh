#!/usr/bin/env bash
set -e

cd /workspace/runpod-slim/ComfyUI

pkill -f "python main.py" 2>/dev/null || true

./.venv-cu128/bin/python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header
