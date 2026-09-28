#!/usr/bin/env python3
import os
import shutil
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

from huggingface_hub import get_hf_file_metadata, hf_hub_download, hf_hub_url

COMFY = Path(os.getenv("CHUD_H3_COMFY", "/opt/chud-h3/ComfyUI"))
MODELS = COMFY / "models"
STAGE = Path(os.getenv("CHUD_H3_STAGE", "/workspace/h3-stage"))
MANIFEST = Path(os.getenv("CHUD_H3_MANIFEST", str(Path(__file__).with_name("model_sources.tsv"))))

os.environ["HF_XET_HIGH_PERFORMANCE"] = "1"
os.environ["HF_HUB_DISABLE_XET"] = "0"
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
STAGE.mkdir(parents=True, exist_ok=True)

GIB = 1024 ** 3
MIB = 1024 ** 2
TOKEN = os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN")

def tree_size(path: Path) -> int:
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                total += os.path.getsize(os.path.join(root, name))
            except OSError:
                pass
    return total

def human_eta(seconds):
    if seconds is None or seconds < 0 or seconds == float("inf"):
        return "--"
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    m, s = divmod(seconds, 60)
    if m < 60:
        return f"{m}m {s:02d}s"
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m"

def hf_size(repo, filename, revision=None):
    try:
        url = hf_hub_url(repo_id=repo, filename=filename, revision=revision or "main")
        meta = get_hf_file_metadata(url, token=TOKEN)
        return int(meta.size) if meta.size is not None else None
    except Exception as exc:
        print(f"[INFO] Could not read remote size: {exc}", flush=True)
        return None

def url_size(url):
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=20) as r:
            n = r.headers.get("Content-Length")
            return int(n) if n else None
    except Exception:
        return None

def progress_worker(stop_event, baseline_bytes, expected_bytes, label):
    last_time = time.monotonic()
    last_bytes = 0
    while not stop_event.wait(5):
        now = time.monotonic()
        current = max(0, tree_size(STAGE) - baseline_bytes)
        dt = max(0.001, now - last_time)
        db = max(0, current - last_bytes)
        speed = db / dt
        if expected_bytes:
            shown = min(current, expected_bytes)
            pct = min(99.9, (shown / expected_bytes) * 100)
            eta = (expected_bytes - shown) / speed if speed > 0 else None
            print(f"[{pct:5.1f}%] {shown/GIB:6.2f}/{expected_bytes/GIB:.2f} GiB | {speed/MIB:6.1f} MiB/s | ETA {human_eta(eta)}", flush=True)
        else:
            print(f"[DOWNLOADING] {label}: {current/GIB:.2f} GiB | {speed/MIB:6.1f} MiB/s", flush=True)
        last_time, last_bytes = now, current

def ready(dest: Path, expected):
    if not dest.exists() or dest.stat().st_size <= 1024 * 1024:
        return False
    if expected:
        return dest.stat().st_size == expected
    return True

print("ChuD MiniMax H3 v2.1 Model Downloader", flush=True)
print("ComfyUI:", COMFY, flush=True)

for raw in MANIFEST.read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split("|")
    scheme = parts[0]

    if scheme == "hf":
        if len(parts) < 4:
            raise ValueError(f"Bad HF manifest line: {line}")
        _, repo, filename, rel, *rest = parts
        revision = rest[0] if rest and rest[0] else None
        dest = MODELS / rel
        expected = hf_size(repo, filename, revision)
        source_label = f"hf://{repo}/{filename}" + (f"@{revision}" if revision else "")
    elif scheme == "url":
        if len(parts) < 3:
            raise ValueError(f"Bad URL manifest line: {line}")
        _, url, rel, *_ = parts
        dest = MODELS / rel
        expected = url_size(url)
        source_label = url
    else:
        raise ValueError(f"Unknown scheme in manifest: {scheme}")

    dest.parent.mkdir(parents=True, exist_ok=True)
    print("\n" + "=" * 64, flush=True)
    print(f"Model: {dest}", flush=True)
    print(f"Source: {source_label}", flush=True)
    if expected:
        print(f"Size: {expected/GIB:.2f} GiB", flush=True)

    if ready(dest, expected):
        print(f"[REUSE] {dest.stat().st_size/GIB:.2f} GiB ✅", flush=True)
        continue

    if scheme == "hf":
        baseline = tree_size(STAGE)
        stop_event = threading.Event()
        monitor = threading.Thread(target=progress_worker, args=(stop_event, baseline, expected, dest.name), daemon=True)
        monitor.start()
        try:
            src = Path(hf_hub_download(repo_id=repo, filename=filename, revision=revision, local_dir=str(STAGE), token=TOKEN))
        finally:
            stop_event.set(); monitor.join(timeout=2)
        shutil.move(str(src), str(dest))
    else:
        subprocess.run(["wget", "-c", url, "-O", str(dest)], check=True)

    if expected and dest.stat().st_size != expected:
        raise RuntimeError(f"Size mismatch for {dest}: got {dest.stat().st_size}, expected {expected}")
    print(f"[READY] {dest.stat().st_size/GIB:.2f} GiB ✅", flush=True)

print("\n✅ All MiniMax H3 v2.1 models READY", flush=True)
