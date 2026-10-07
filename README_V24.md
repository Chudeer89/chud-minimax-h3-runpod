# ChuD MiniMax H3 v2.4 — Modular Video Studio

v2.4 keeps the proven MiniMax H3 v2.3.1 stack as the core and adds optional specialist modules instead of forcing every job through every model.

## Architecture

- H3 Core: prompt + image + video + audio generation, Ref2VA, FaceRefine, 2K final.
- Thai Voice: IndexTTS2 Thai LoRA sidecar on port 7865. H3 audio can be supplied as emotion reference; final Thai speech comes from the Thai TTS output.
- LTX-2.5: optional VFX branch for Alpha/Matting, Refine Details, controls and upscale.
- Wan2.2 Animate: optional motion / character replacement branch.

The modules are independent. They can be enabled only when a job needs them so an L40S does not have to keep all large models resident at once.

## Runtime switches

Set CHUD_V24_MODULES to a comma-separated list:

- none: H3 only
- tts: H3 + Thai TTS bridge
- ltx: H3 + LTX ComfyUI nodes
- wan: H3 + WanVideoWrapper
- tts,ltx,wan: install all optional code modules

Large LTX/Wan weights are NOT downloaded automatically by the image. This is intentional to avoid exhausting /workspace. Use the module model manifests when the branch is enabled for a project.

## Thai voice design

ComfyUI node: ChuD Thai TTS (IndexTTS2)

Inputs:
- text: exact Thai dialogue
- voice_audio: speaker/timbre reference
- emotion_audio: optional H3-generated audio used only for emotion/prosody reference
- emotion_alpha: 0.0–1.0
- seed
- server_url (default http://127.0.0.1:7865)

Output:
- AUDIO suitable for H3 Audio Lock or direct final mux.

IndexTTS2 currently requires Python < 3.12, while the H3 ComfyUI runtime is Python 3.12. v2.4 therefore runs Thai TTS in an isolated Python 3.11 environment. It does not downgrade or replace the locked H3 Torch stack.

## Pinned optional sources

- Lightricks/ComfyUI-LTXVideo @ 3bf3ca62595f1764c47d01c35c8e5dfe47e1a88f
- kijai/ComfyUI-WanVideoWrapper @ 088128b224242e110d3906c6750e9a3a348a659b
- dubbing-ai/indextts2-thai @ 1a5ef7de72b8a39408581153d45307be29a20c0d

## Safety / stability

v2.3.1 remains untouched as the fallback.
v2.4 never changes the locked H3 Torch 2.10.0+cu130 environment.
Optional models are loaded as separate stages and should be unloaded between stages on 48 GB GPUs.
