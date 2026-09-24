#!/usr/bin/env python3

import os
import shutil
import threading
import time
from pathlib import Path

from huggingface_hub import get_hf_file_metadata, hf_hub_download, hf_hub_url

COMFY = Path(os.getenv("CHUD_H3_COMFY", "/opt/chud-h3/ComfyUI"))
MODELS = COMFY / "models"
STAGE = Path(os.getenv("CHUD_H3_STAGE", "/workspace/h3-stage"))
MANIFEST = Path(__file__).with_name("model_sources.tsv")

os.environ["HF_XET_HIGH_PERFORMANCE"] = "1"
os.environ["HF_HUB_DISABLE_XET"] = "0"
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"

STAGE.mkdir(parents=True, exist_ok=True)

GIB = 1024 ** 3
MIB = 1024 ** 2


def tree_size(path: Path) -> int:
    total = 0
    try:
        for root, _, files in os.walk(path):
            for name in files:
                p = os.path.join(root, name)
                try:
                    total += os.path.getsize(p)
                except OSError:
                    pass
    except OSError:
        pass
    return total


def human_eta(seconds):
    if seconds is None or seconds < 0 or seconds == float("inf"):
        return "--"
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    minutes, sec = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m {sec:02d}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes:02d}m"


def get_remote_size(repo: str, filename: str):
    token = os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN")
    try:
        url = hf_hub_url(repo_id=repo, filename=filename)
        meta = get_hf_file_metadata(url, token=token)
        return int(meta.size) if meta.size is not None else None
    except Exception as exc:
        print(f"[INFO] Could not read remote size: {exc}", flush=True)
        return None


def progress_worker(stop_event, baseline_bytes, expected_bytes, label):
    started = time.monotonic()
    last_time = started
    last_bytes = 0

    while not stop_event.wait(5):
        now = time.monotonic()
        current = max(0, tree_size(STAGE) - baseline_bytes)
        delta_t = max(0.001, now - last_time)
        delta_b = max(0, current - last_bytes)
        speed = delta_b / delta_t

        if expected_bytes:
            shown = min(current, expected_bytes)
            pct = min(99.9, (shown / expected_bytes) * 100)
            remaining = max(0, expected_bytes - shown)
            eta = remaining / speed if speed > 0 else None
            print(
                f"[{pct:5.1f}%] {shown / GIB:6.2f} / {expected_bytes / GIB:.2f} GiB"
                f" | {speed / MIB:6.1f} MiB/s | ETA {human_eta(eta)}",
                flush=True,
            )
        else:
            print(
                f"[DOWNLOADING] {label}: {current / GIB:.2f} GiB"
                f" | {speed / MIB:6.1f} MiB/s",
                flush=True,
            )

        last_time = now
        last_bytes = current


print("ChuD MiniMax H3 Model Downloader", flush=True)
print("ComfyUI:", COMFY, flush=True)

for line in MANIFEST.read_text().splitlines():
    line = line.strip()

    if not line:
        continue

    repo, filename, rel = line.split("|", 2)
    dest = MODELS / rel
    dest.parent.mkdir(parents=True, exist_ok=True)

    print("\n" + "=" * 58, flush=True)
    print(f"Downloading: {dest.name}", flush=True)

    if dest.exists() and dest.stat().st_size > 1024 * 1024:
        gb = dest.stat().st_size / GIB
        print(f"[REUSE] {gb:.2f} GiB", flush=True)
        print(f"✅ {dest.name} READY", flush=True)
        print("=" * 58, flush=True)
        continue

    expected = get_remote_size(repo, filename)
    if expected:
        print(f"Size: {expected / GIB:.2f} GiB", flush=True)
    else:
        print("Size: unknown", flush=True)
    print("=" * 58, flush=True)
    print(f"Source: {repo}", flush=True)

    baseline = tree_size(STAGE)
    stop_event = threading.Event()
    monitor = threading.Thread(
        target=progress_worker,
        args=(stop_event, baseline, expected, dest.name),
        daemon=True,
    )
    monitor.start()

    try:
        src = Path(
            hf_hub_download(
                repo_id=repo,
                filename=filename,
                local_dir=str(STAGE),
                token=os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN"),
            )
        )
    finally:
        stop_event.set()
        monitor.join(timeout=2)

    shutil.move(str(src), str(dest))

    gb = dest.stat().st_size / GIB
    print(f"[100.0%] {gb:6.2f} / {gb:.2f} GiB", flush=True)
    print(f"✅ {dest.name} READY", flush=True)
    print("=" * 58, flush=True)

print("\n✅ All MiniMax H3 models READY", flush=True)
