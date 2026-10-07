import os
import sys
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

import torch
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

ROOT = Path(os.getenv("CHUD_THAI_TTS_ROOT", "/workspace/chud-v24/index-tts-thai"))
SRC = Path(os.getenv("CHUD_THAI_TTS_SRC", str(ROOT / "src_repo")))
CHECKPOINTS = Path(os.getenv("CHUD_THAI_TTS_CHECKPOINTS", str(ROOT / "checkpoints")))
LORA = os.getenv("CHUD_THAI_TTS_LORA", str(ROOT / "thai_lora"))
OUT = ROOT / "outputs"
TMP = ROOT / "tmp"
for p in (OUT, TMP):
    p.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(SRC))
from src.inference_thai import load_thai_model

tts = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global tts
    device = os.getenv("CHUD_THAI_TTS_DEVICE", "cuda:0")
    use_fp16 = os.getenv("CHUD_THAI_TTS_FP16", "1") == "1"
    print(f"[ChuD Thai TTS] loading on {device} ...", flush=True)
    tts = load_thai_model(
        model_dir=str(CHECKPOINTS),
        cfg_path=str(CHECKPOINTS / "config.yaml"),
        lora_path=LORA,
        device=device,
        use_fp16=use_fp16,
    )
    print("[ChuD Thai TTS] READY", flush=True)
    yield
    tts = None


app = FastAPI(title="ChuD Thai TTS", version="2.4", lifespan=lifespan)


@app.get("/health")
def health():
    return {"status": "ok" if tts is not None else "loading", "model_loaded": tts is not None}


def save_upload(upload: UploadFile, path: Path):
    with path.open("wb") as f:
        f.write(upload.file.read())


@app.post("/v1/tts")
def generate(
    text: str = Form(...),
    voice: UploadFile = File(...),
    emotion_audio: UploadFile | None = File(None),
    emotion_alpha: float = Form(0.85),
    temperature: float = Form(0.8),
    seed: int = Form(42),
):
    if tts is None:
        raise HTTPException(status_code=503, detail="Thai TTS model is still loading")
    job = uuid.uuid4().hex[:12]
    voice_path = TMP / f"{job}_voice.wav"
    emo_path = TMP / f"{job}_emotion.wav"
    out_path = OUT / f"{job}.wav"
    save_upload(voice, voice_path)
    if emotion_audio is not None:
        save_upload(emotion_audio, emo_path)

    try:
        kwargs = {
            "temperature": float(temperature),
        }
        if emotion_audio is not None:
            kwargs["emo_audio_prompt"] = str(emo_path)
            kwargs["emo_alpha"] = float(emotion_alpha)
        tts.infer(
            spk_audio_prompt=str(voice_path),
            text=text,
            output_path=str(out_path),
            seed=int(seed),
            **kwargs,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Inference failed: {exc}")
    finally:
        voice_path.unlink(missing_ok=True)
        emo_path.unlink(missing_ok=True)

    if not out_path.exists():
        raise HTTPException(status_code=500, detail="TTS produced no output file")
    return FileResponse(str(out_path), media_type="audio/wav", filename="thai_tts.wav")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("CHUD_THAI_TTS_PORT", "7865")))
