#!/usr/bin/env python3
"""Download every model in the manifest, several files at a time, with overall progress.

Manifest lines:  hf|repo|file-in-repo|dest-under-models|revision(optional)
                 url|https://...|dest-under-models
Env: CHUD_H3_COMFY, CHUD_H3_STAGE, CHUD_H3_MANIFEST, CHUD_H3_PARALLEL (default 4), HF_TOKEN
"""
import os
import shutil
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

os.environ["HF_XET_HIGH_PERFORMANCE"] = "1"
os.environ["HF_HUB_DISABLE_XET"] = "0"
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"

from huggingface_hub import get_hf_file_metadata, hf_hub_download, hf_hub_url  # noqa: E402

COMFY = Path(os.getenv("CHUD_H3_COMFY", "/opt/chud-h3/ComfyUI"))
MODELS = COMFY / "models"
STAGE = Path(os.getenv("CHUD_H3_STAGE", "/workspace/h3-stage"))
MANIFEST = Path(os.getenv("CHUD_H3_MANIFEST", str(Path(__file__).with_name("model_sources.tsv"))))
PARALLEL = max(1, int(os.getenv("CHUD_H3_PARALLEL", "4")))
TOKEN = os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN")
RETRIES = 3
GIB = 1024 ** 3
MIB = 1024 ** 2


def say(msg):
    print(msg, flush=True)


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
    m, s = divmod(seconds, 60)
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m" if h else (f"{m}m {s:02d}s" if m else f"{s}s")


def remote_size(job):
    try:
        if job["scheme"] == "hf":
            url = hf_hub_url(repo_id=job["repo"], filename=job["file"], revision=job["rev"] or "main")
            meta = get_hf_file_metadata(url, token=TOKEN)
            return int(meta.size) if meta.size is not None else None
        req = urllib.request.Request(job["url"], method="HEAD", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as r:
            n = r.headers.get("Content-Length")
            return int(n) if n else None
    except Exception as exc:
        say(f"[INFO] could not read size of {job['dest'].name}: {exc}")
        return None


def parse_manifest():
    jobs = []
    for raw in MANIFEST.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        p = line.split("|")
        if p[0] == "hf" and len(p) >= 4:
            jobs.append({"scheme": "hf", "repo": p[1], "file": p[2], "dest": MODELS / p[3],
                         "rev": p[4] if len(p) > 4 and p[4] else None})
        elif p[0] == "url" and len(p) >= 3:
            jobs.append({"scheme": "url", "url": p[1], "dest": MODELS / p[2], "rev": None})
        else:
            raise ValueError(f"Bad manifest line: {line}")
    return jobs


def is_ready(job):
    d = job["dest"]
    if not d.exists() or d.stat().st_size <= 1024 * 1024:
        return False
    return job["size"] is None or d.stat().st_size == job["size"]


def fetch(job):
    stage = STAGE / f"job{job['index']:02d}"
    stage.mkdir(parents=True, exist_ok=True)
    job["stage"] = stage
    if job["scheme"] == "hf":
        src = Path(hf_hub_download(repo_id=job["repo"], filename=job["file"], revision=job["rev"],
                                   local_dir=str(stage), token=TOKEN))
    else:
        src = stage / job["dest"].name
        req = urllib.request.Request(job["url"], headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as r, open(src, "wb") as out:
            shutil.copyfileobj(r, out, 8 * MIB)
    job["dest"].parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(job["dest"]))
    shutil.rmtree(stage, ignore_errors=True)
    if job["size"] and job["dest"].stat().st_size != job["size"]:
        raise RuntimeError(f"size mismatch: got {job['dest'].stat().st_size}, expected {job['size']}")


def fetch_with_retry(job):
    for attempt in range(1, RETRIES + 1):
        try:
            job["state"] = "downloading"
            fetch(job)
            job["state"] = "done"
            return job
        except Exception as exc:
            say(f"[RETRY {attempt}/{RETRIES}] {job['dest'].name}: {exc}")
            time.sleep(5 * attempt)
    job["state"] = "failed"
    raise RuntimeError(f"failed after {RETRIES} attempts: {job['dest'].name}")


def monitor(jobs, todo_bytes, stop):
    start = last_t = time.monotonic()
    last_b = 0
    while not stop.wait(10):
        done_b, active = 0, []
        for j in jobs:
            if j["state"] == "done":
                done_b += j["size"] or 0
            elif j["state"] == "downloading":
                got = tree_size(j.get("stage", STAGE / "none"))
                done_b += got
                if j["size"]:
                    active.append(f"{j['dest'].name[:38]} {min(99.9, got * 100 / j['size']):.0f}%")
        now = time.monotonic()
        speed = max(0, done_b - last_b) / max(0.001, now - last_t)
        avg = done_b / max(0.001, now - start)
        pct = min(99.9, done_b * 100 / todo_bytes) if todo_bytes else 0
        eta = (todo_bytes - done_b) / avg if avg > 0 else None
        n_done = sum(j["state"] == "done" for j in jobs)
        say(f"[{pct:5.1f}%] {done_b / GIB:6.1f}/{todo_bytes / GIB:.1f} GiB | {speed / MIB:6.0f} MiB/s | "
            f"ETA {human_eta(eta)} | files {n_done}/{len(jobs)} | " + ", ".join(active))
        last_t, last_b = now, done_b


def main():
    say("=" * 64)
    say(f"ChuD MiniMax H3 model downloader | ComfyUI: {COMFY} | parallel: {PARALLEL}")
    jobs = parse_manifest()
    with ThreadPoolExecutor(max_workers=8) as ex:
        for job, size in zip(jobs, ex.map(remote_size, jobs)):
            job["size"] = size
    for i, j in enumerate(jobs):
        j["index"], j["state"] = i, "queued"

    ready = [j for j in jobs if is_ready(j)]
    todo = [j for j in jobs if not is_ready(j)]
    all_b = sum(j["size"] or 0 for j in jobs)
    todo_b = sum(j["size"] or 0 for j in todo)
    say(f"Models: {len(jobs)} files, {all_b / GIB:.1f} GiB total | already here: {len(ready)} | "
        f"to download: {len(todo)} files, {todo_b / GIB:.1f} GiB")
    for j in ready:
        say(f"[REUSE] {j['dest'].relative_to(MODELS)}")
    if not todo:
        say("✅ All MiniMax H3 models READY")
        return

    MODELS.mkdir(parents=True, exist_ok=True)
    STAGE.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(STAGE).free
    say(f"Disk free on volume: {free / GIB:.1f} GiB")
    if free < todo_b + 2 * GIB:
        say(f"❌ NOT ENOUGH DISK: need about {(todo_b + 2 * GIB) / GIB:.1f} GiB, have {free / GIB:.1f} GiB. "
            "Increase the pod's Volume Disk and restart.")
        raise SystemExit(1)

    stop = threading.Event()
    mon = threading.Thread(target=monitor, args=(todo, todo_b, stop), daemon=True)
    mon.start()
    t0 = time.monotonic()
    failed = []
    # biggest files first so the long downloads overlap with the small ones
    todo.sort(key=lambda j: -(j["size"] or 0))
    with ThreadPoolExecutor(max_workers=PARALLEL) as ex:
        futures = {ex.submit(fetch_with_retry, j): j for j in todo}
        for fut in as_completed(futures):
            j = futures[fut]
            try:
                fut.result()
                say(f"[READY] {j['dest'].relative_to(MODELS)} ({(j['size'] or 0) / GIB:.2f} GiB) ✅")
            except Exception as exc:
                failed.append(j)
                say(f"[FAILED] {j['dest'].relative_to(MODELS)}: {exc}")
    stop.set()
    mon.join(timeout=2)
    mins = (time.monotonic() - t0) / 60
    if failed:
        say(f"❌ {len(failed)} model(s) failed: " + ", ".join(j["dest"].name for j in failed))
        raise SystemExit(1)
    say(f"✅ All MiniMax H3 models READY ({todo_b / GIB:.1f} GiB in {mins:.1f} min)")


if __name__ == "__main__":
    main()
