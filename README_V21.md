# ChuD MiniMax H3 SEEDHUNTER v2.1

This branch is the reproducible v2.1 setup captured on 2026-09-28.

## What is preserved

- Locked ComfyUI/custom-node revisions
- MiniMax H3 Ref2VA + FL2VA models
- Qwen3VL MiniMax H3 text encoder
- FP16 + Kijai INT8 Video VAE and Audio VAE
- MiniMax H3 latent upscaler FP16
- TaeH3 preview model
- v2.1 Silver DARE-TIES Turbo LoRA
- Additional H3 LoRAs: Realism People, Better Motion, MysticXXX Ref2VA, Turbo v4 step600, 8-step FL2V, 4-step Ref2V
- RIFE flownet auto-download
- v2.1 workflow JSON

## New RunPod / another RunPod account

Start from the same RunPod ComfyUI CUDA 13 template, open **Web Terminal / Ubuntu Terminal**, then run:

```bash
cd /workspace
git clone -b h3-v2.1 https://github.com/Chudeer89/chud-minimax-h3-runpod.git chud-h3-v21
bash /workspace/chud-h3-v21/restore-v21.sh
```

When restore finishes, start ComfyUI:

```bash
cd /workspace/runpod-slim/ComfyUI
source .venv-cu128/bin/activate
python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header
```

Then audit from a second Web Terminal:

```bash
bash /workspace/chud-h3-v21/audit-v21.sh
```

## Important

The GitHub repo stores setup code, locks, URLs, and workflow—not the 60+ GB model binaries. A completely new Pod/account still downloads those bytes once from the model sources. The process is automatic and reuses any already-present correctly sized files.
