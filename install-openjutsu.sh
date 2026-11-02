#!/usr/bin/env bash
# MV image only (Dockerfile.mv-openjutsu), run at build time on top of the v24 MV image (Krea 2 + X2 stay as they are):
# ComfyUI core -> v0.43.2 (Openjutsu needs 0.41.2+ for native H3, SAM 3.1, TextGenerate; the MOSS + Krea 2 stills mix
# needs 0.43 for CLIPLoader moss_image, ResolutionSelector, Math/Switch), the Openjutsu node packs,
# Node 22, the Openjutsu app and comfy-api-proxy 0.1.6. The film image (Dockerfile, install-nodes.sh) never runs this.
set -euo pipefail

COMFY=/opt/comfyui-baked
PY=python3.12
LOCK=/opt/chud-h3/nodes.openjutsu.lock
COMFY_COMMIT=423cbd20511becb1f16122ab518e92e58bfa03d9   # ComfyUI v0.43.2
NODE_VERSION=22.23.4
OPENJUTSU_COMMIT=7fe118bb5a61fcfac0148e1bfea3dd29884dbf26
APP=/opt/openjutsu
PROXY_VERSION=0.1.6

echo "===== MV Openjutsu: runtime constraints of the base ====="
ls -la /usr/lib/python3.12/EXTERNALLY-MANAGED 2>/dev/null && echo "WARN: EXTERNALLY-MANAGED marker present" || true
cat /opt/comfyui-runtime-constraints.txt || true
# Keep the Torch/CUDA pins, drop the frontend/aimdo pins that ComfyUI 0.41.2 raises in its own requirements.txt.
grep -viE '^(comfyui-frontend-package|comfyui-workflow-templates|comfyui-embedded-docs|comfy-aimdo|comfy-kitchen)([<>=! ]|$)' \
    /opt/comfyui-runtime-constraints.txt > /tmp/oj-constraints.txt || true
PIP=("$PY" -m pip install --no-cache-dir -c /tmp/oj-constraints.txt)
TORCH_BEFORE=$("$PY" -c 'import torch; print(torch.__version__)')

echo
echo "===== ComfyUI core -> v0.43.2 ====="
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
    # GitHub resets a clone now and then mid-build (2026-11-02 SolarRenderer), so try three times
    for try in 1 2 3; do
        rm -rf "$dst"
        git clone --filter=blob:none --no-tags "$repo" "$dst" && break
        [ "$try" = 3 ] && exit 1
        echo "clone failed, retrying in 10 s"; sleep 10
    done
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
curl -fsSLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz"
curl -fsSLO "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt"
grep " node-v$NODE_VERSION-linux-x64.tar.gz\$" SHASUMS256.txt | sha256sum -c -
mkdir -p /opt/node22
tar -xzf "node-v$NODE_VERSION-linux-x64.tar.gz" -C /opt/node22 --strip-components=1
rm -f "node-v$NODE_VERSION-linux-x64.tar.gz" SHASUMS256.txt
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
# Debian's python3.12 has no ensurepip without the python3.12-venv package, so the venv is made without pip and the
# image's own pip installs into it (--python).
"$PY" -m venv --without-pip "$APP/.venv-proxy"
"$PY" -m pip --python "$APP/.venv-proxy/bin/python" install --no-cache-dir -q "comfy-api-proxy==$PROXY_VERSION"
"$APP/.venv-proxy/bin/python" "$APP/patch_proxy.py"

echo
echo "===== Node import check (CPU start, on a throw-away copy) ====="
# No GPU on the build runner: --cpu --quick-test-for-ci starts ComfyUI once, which imports every node pack, then exits.
# Informational only; the list of failed packs is what to look at before a pod run.
rm -rf /tmp/comfy-check && cp -a "$COMFY" /tmp/comfy-check
( cd /tmp/comfy-check && timeout 900 "$PY" main.py --cpu --quick-test-for-ci --disable-auto-launch ) \
    > /tmp/comfy-check.log 2>&1 || true
grep -E "IMPORT FAILED" /tmp/comfy-check.log || echo "no IMPORT FAILED"
# the full traceback of every pack that did not load (ComfyUI prints it just before "Cannot import ...")
awk '/Traceback \(most recent call last\)/ {buf=""; keep=1} keep {buf = buf $0 "\n"}
     /Cannot import .* module for custom nodes/ {print "----- " $0; printf "%s", buf; keep=0; buf=""}' /tmp/comfy-check.log \
    | tail -200
rm -rf /tmp/comfy-check /tmp/comfy-check.log

echo
echo "===== MV Openjutsu ready (torch $TORCH_AFTER) ====="
