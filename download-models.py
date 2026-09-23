#!/usr/bin/env python3

import os
import shutil
from pathlib import Path
from huggingface_hub import hf_hub_download

COMFY = Path(os.getenv("CHUD_H3_COMFY", "/opt/chud-h3/ComfyUI"))
MODELS = COMFY / "models"
STAGE = Path(os.getenv("CHUD_H3_STAGE", "/workspace/h3-stage"))
MANIFEST = Path(__file__).with_name("model_sources.tsv")

os.environ["HF_XET_HIGH_PERFORMANCE"] = "1"
os.environ["HF_HUB_DISABLE_XET"] = "0"

STAGE.mkdir(parents=True, exist_ok=True)

print("ChuD MiniMax H3 Model Downloader")
print("ComfyUI:", COMFY)

for line in MANIFEST.read_text().splitlines():
    line = line.strip()

    if not line:
        continue

    repo, filename, rel = line.split("|", 2)
    dest = MODELS / rel
    dest.parent.mkdir(parents=True, exist_ok=True)

    print("\nMODEL:", dest.name)

    if dest.exists() and dest.stat().st_size > 1024 * 1024:
        gb = dest.stat().st_size / (1024 ** 3)
        print(f"[REUSE] {gb:.2f} GiB")
        continue

    print("[DOWNLOAD]", repo)
    src = Path(hf_hub_download(
        repo_id=repo,
        filename=filename,
        local_dir=str(STAGE)
    ))

    shutil.move(str(src), str(dest))

    gb = dest.stat().st_size / (1024 ** 3)
    print(f"[OK] {gb:.2f} GiB")

print("\nAll MiniMax H3 models READY")
