# ChuD MiniMax H3 v2.4 — Modular Video Studio

v2.4 keeps the proven v2.3.1 runtime as the fallback, but the primary H3 workflow is now the verified official Seed Hunter v2.5 workflow (CivitAI model version 3383710, SHA256 5e624e2bfc49a32cf4529fce659275a15869532267e91df8d569774636f84451). Optional specialist modules are added around it instead of forcing every job through every model.

## Architecture

- H3 Core: official Seed Hunter v2.5, including Dialogue / Voice Clone seed hunting, redesigned controls, independent stage-1/stage-2 sparse-attention toggles, corrected LoRA loader, prompt/image/video/audio generation, Ref2VA, FaceRefine, and 2K final.
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


## Seed Hunter v2.5 integration

The GitHub Actions build downloads the creator's corrected 2026-10-05 v2.5 workflow directly from CivitAI and verifies its full SHA256 before building the image. A hash mismatch fails the build instead of silently accepting a changed workflow.

v2.5 support pins the current releases of Pixaroma, H3 Prompt IDE, Fantastic MiniMaxH3 PromptBuilder, MiniMaxH3Mod, and the MiniMax H3 latent upscaler. The Kijai DMAD 4-step LoRA is added to the H3 model manifest; the creator recommends 8 sampling steps at strength 1.0.

The original v2.1 workflow remains installed beside v2.5 as a recovery reference.


## Seed Hunter v2.5 required model

The v2.5 workflow selects `Minimax-h3_Singularity_ref2va_Pruned_v1.3_int8.safetensors` by default. v24 now downloads/reuses that exact checkpoint automatically into `models/diffusion_models/`, so ComfyUI should no longer show it as a Missing Model after a fresh v24 Pod finishes model setup.
