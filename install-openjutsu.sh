#!/usr/bin/env bash
# MV image only (Dockerfile.mv-openjutsu), run at build time on top of the v24 MV image (Krea 2 + X2 stay as they are):
# ComfyUI core -> v0.41.2 (Openjutsu needs native H3, SAM 3.1 and TextGenerate from 0.41.2), the Openjutsu node packs,
# Node 22, the Openjutsu app and comfy-api-proxy 0.1.6. The film image (Dockerfile, install-nodes.sh) never runs this.
set -euo pipefail

COMFY=/opt/comfyui-baked
PY=python3.12
LOCK=/opt/chud-h3/nodes.openjutsu.lock
COMFY_COMMIT=b53f77a74e21091cbdebfdf7b85fc80326932646   # ComfyUI v0.41.2
NODE_VERSION=22.23.4
OPENJUTSU_COMMIT=7fe118bb5a61fcfac0148e1bfea3dd29884dbf26
APP=/opt/openjutsu
PROXY_VERSION=0.1.6

echo "===== MV Openjutsu: runtime constraints of the base ====="
cat /opt/comfyui-runtime-constraints.txt || true
# Keep the Torch/CUDA pins, drop the frontend/aimdo pins that ComfyUI 0.41.2 raises in its own requirements.txt.
grep -viE '^(comfyui-frontend-package|comfyui-workflow-templates|comfyui-embedded-docs|comfy-aimdo|comfy-kitchen)([<>=! ]|$)' \
    /opt/comfyui-runtime-constraints.txt > /tmp/oj-constraints.txt || true
PIP=("$PY" -m pip install --no-cache-dir -c /tmp/oj-constraints.txt)
TORCH_BEFORE=$("$PY" -c 'import torch; print(torch.__version__)')

echo
echo "===== ComfyUI core -> v0.41.2 ====="
test -d "$COMFY/.git" || { echo "ERROR: $COMFY is not a git checkout"; exit 1; }
git -C "$COMFY" fetch --no-tags origin "$COMFY_COMMIT"
git -C "$COMFY" checkout -f "$COMFY_COMMIT"
"${PIP[@]}" -r "$COMFY/requirements.txt"

echo
echo "===== Openjutsu node packs ====="
while IFS='|' read -r name repo commit; do
    name="${name%$'\r'}"; repo="${repo%$'\r'}"; commit="${commit%$'\r'}"
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    echo "--- $name @ $commit"
    dst="$COMFY/custom_nodes/$name"
    rm -rf "$dst"
    git clone --filter=blob:none --no-tags "$repo" "$dst"
    git -C "$dst" fetch --no-tags origin "$commit" >/dev/null 2>&1 || true
    git -C "$dst" checkout -f "$commit"
    if [ -f "$dst/requirements.txt" ]; then
        # controlnet_aux: only Metric3D is used. Its opencv-python would shadow the headless cv2 the other packs use,
        # and mediapipe / onnxruntime-gpu are for preprocessors Openjutsu never runs.
        grep -viE '^(opencv-python|mediapipe|onnxruntime)([<>=!; ]|$)' "$dst/requirements.txt" > /tmp/oj-req.txt || true
        "${PIP[@]}" -r /tmp/oj-req.txt
    fi
    # SolarRenderer's pyproject pins torch<2.9 for its standalone CLI; the ComfyUI nodes run in ComfyUI's own Python,
    # so the package itself is never pip-installed.
done < "$LOCK"

TORCH_AFTER=$("$PY" -c 'import torch; print(torch.__version__)')
if [ "$TORCH_BEFORE" != "$TORCH_AFTER" ]; then
    echo "ERROR: torch changed from $TORCH_BEFORE to $TORCH_AFTER"
    exit 1
fi

echo
echo "===== Node.js $NODE_VERSION ====="
cd /tmp
curl -fsSLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz"
curl -fsSLO "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt"
grep " node-v$NODE_VERSION-linux-x64.tar.xz\$" SHASUMS256.txt | sha256sum -c -
mkdir -p /opt/node22
tar -xJf "node-v$NODE_VERSION-linux-x64.tar.xz" -C /opt/node22 --strip-components=1
rm -f "node-v$NODE_VERSION-linux-x64.tar.xz" SHASUMS256.txt
export PATH=/opt/node22/bin:$PATH
node --version

echo
echo "===== Openjutsu app @ $OPENJUTSU_COMMIT ====="
rm -rf "$APP"
git clone --filter=blob:none --no-tags https://github.com/D3voz/openjutsu.git "$APP"
git -C "$APP" checkout -f "$OPENJUTSU_COMMIT"
# Comfy-Org ships no int4_convrot H3 text encoder; the v24 image already has the nvfp4_awq one, so default to that.
grep -rlF qwen3vl_32b_minimax_h3_int4_convrot.safetensors "$APP/lib" "$APP/workflows" \
    | xargs sed -i 's/qwen3vl_32b_minimax_h3_int4_convrot\.safetensors/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors/g'
cat > "$APP/.env.local" <<'ENV'
COMFY_BASE_URL=http://127.0.0.1:8189
COMFY_API_KEY=
COMFYUI_URL=http://127.0.0.1:8188
ENV
cd "$APP"
NEXT_TELEMETRY_DISABLED=1 npm ci --no-audit --no-fund
NEXT_TELEMETRY_DISABLED=1 npm run build

echo
echo "===== SolarRenderer long-clip fix (from Openjutsu) ====="
SOLAR="$COMFY/custom_nodes/SolarRenderer"
if git -C "$SOLAR" apply --check "$APP/patches/solarrenderer-long-clips.patch" 2>/dev/null; then
    git -C "$SOLAR" apply "$APP/patches/solarrenderer-long-clips.patch"
    echo "applied"
else
    echo "not needed (already fixed upstream or changed)"
fi

echo
echo "===== comfy-api-proxy $PROXY_VERSION (own venv) ====="
"$PY" -m venv "$APP/.venv-proxy"
"$APP/.venv-proxy/bin/python" -m pip install --no-cache-dir -q "comfy-api-proxy==$PROXY_VERSION"
"$APP/.venv-proxy/bin/python" "$APP/patch_proxy.py"

echo
echo "===== MV Openjutsu ready (torch $TORCH_AFTER) ====="
