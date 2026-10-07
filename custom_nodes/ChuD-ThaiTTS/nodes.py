import io
import requests
import torch
import torchaudio


def _audio_to_wav_bytes(audio):
    if not isinstance(audio, dict) or "waveform" not in audio or "sample_rate" not in audio:
        raise ValueError("Expected a ComfyUI AUDIO object with waveform and sample_rate.")
    wav = audio["waveform"]
    sr = int(audio["sample_rate"])
    if wav.ndim == 3:
        wav = wav[0]
    elif wav.ndim == 1:
        wav = wav.unsqueeze(0)
    wav = wav.detach().to("cpu", dtype=torch.float32)
    buf = io.BytesIO()
    torchaudio.save(buf, wav, sr, format="wav")
    return buf.getvalue()


def _wav_bytes_to_audio(data):
    buf = io.BytesIO(data)
    wav, sr = torchaudio.load(buf, format="wav")
    return {"waveform": wav.unsqueeze(0), "sample_rate": int(sr)}


class ChuDThaiTTS:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "text": ("STRING", {"multiline": True, "default": "สวัสดีครับ"}),
                "voice_audio": ("AUDIO",),
                "emotion_alpha": ("FLOAT", {"default": 0.85, "min": 0.0, "max": 1.0, "step": 0.05}),
                "temperature": ("FLOAT", {"default": 0.8, "min": 0.1, "max": 1.5, "step": 0.05}),
                "seed": ("INT", {"default": 42, "min": 0, "max": 0x7FFFFFFF}),
                "server_url": ("STRING", {"default": "http://127.0.0.1:7865"}),
            },
            "optional": {
                "emotion_audio": ("AUDIO",),
            },
        }

    RETURN_TYPES = ("AUDIO", "STRING")
    RETURN_NAMES = ("audio", "status")
    FUNCTION = "generate"
    CATEGORY = "ChuD v24/Thai Audio"

    def generate(self, text, voice_audio, emotion_alpha, temperature, seed, server_url, emotion_audio=None):
        base = server_url.rstrip("/")
        try:
            health = requests.get(base + "/health", timeout=5)
            health.raise_for_status()
        except Exception as exc:
            raise RuntimeError(
                "ChuD Thai TTS sidecar is not ready on port 7865. "
                "Check /workspace/thai-tts-setup.log and /workspace/thai-tts.log. "
                f"Details: {exc}"
            )

        files = {
            "voice": ("voice.wav", _audio_to_wav_bytes(voice_audio), "audio/wav"),
        }
        if emotion_audio is not None:
            files["emotion_audio"] = ("emotion.wav", _audio_to_wav_bytes(emotion_audio), "audio/wav")

        data = {
            "text": text,
            "emotion_alpha": str(float(emotion_alpha)),
            "temperature": str(float(temperature)),
            "seed": str(int(seed)),
        }
        response = requests.post(base + "/v1/tts", data=data, files=files, timeout=600)
        if response.status_code != 200:
            raise RuntimeError(f"Thai TTS failed: HTTP {response.status_code}: {response.text[:1000]}")

        audio = _wav_bytes_to_audio(response.content)
        status = "IndexTTS2 Thai OK"
        if emotion_audio is not None:
            status += " | H3/other emotion reference applied"
        return (audio, status)


NODE_CLASS_MAPPINGS = {
    "ChuDThaiTTS": ChuDThaiTTS,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "ChuDThaiTTS": "ChuD Thai TTS (IndexTTS2 + Thai LoRA)",
}
