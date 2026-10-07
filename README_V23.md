# ChuD MiniMax H3 v2.3

v2.3 is built separately from v2.2. The v2.2 branch and image stay untouched as the fallback.

## Core
- ComfyUI v0.39.0
- Torch 2.10.0+cu130 (unchanged)
- CUDA 13.0 (unchanged)
- comfy-kitchen 0.2.37
- comfyui-frontend-package 1.53.10

## New / updated
- comfyui-minimax-h3-audio-T8 v1.94.0 (compatibility update only)
- ComfyUI-H3-FaceRefine 1.1.2
- MiniMax H3 Fun ControlNet-Union model patch
- SDPose whole-body models for pose control
- face_yolov8m + person_yolov8m-seg for FaceRefine
- MiniMaxH3AddGuide / Multiframe support from ComfyUI core

## Images
- v23: ghcr.io/chudeer89/chud-minimax-h3-runpod:v23
- fallback: ghcr.io/chudeer89/chud-minimax-h3-runpod:v22

## Audio policy
Keep the existing H3 audio VAE and existing audio workflow behavior for now. Do not enable the new experimental audio modes by default.
