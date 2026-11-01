#!/usr/bin/env python3
"""Copy a LoRA into ComfyUI, renaming diffusers FLUX.3 keys to ComfyUI's Flux3 module names.

ComfyUI 0.41.2 maps no diffusers key names for Flux3, so a LoRA from diffusers' train_dreambooth_lora_flux3_klein*
(transformer.mode_blocks.image.0.attn.to_q.lora_A.weight ...) would load with every key skipped. Both sides split the
SwiGLU input as gate first, then up, so the rename alone is enough; q/k/v land on ComfyUI's q_proj/k_proj/v_proj, which
it also maps onto a fused qkv. Any other file is copied unchanged.
  convert_lora_keys.py SRC DST
"""
import os
import re
import shutil
import sys

from safetensors import safe_open
from safetensors.torch import save_file

BLOCKS = [
    (re.compile(r"^transformer\.mode_blocks\.(image|image_cond)\.(\d+)\."), r"diffusion_model.content_mode_blocks.\1.\2."),
    (re.compile(r"^transformer\.txt_mode_blocks\.(\d+)\."), r"diffusion_model.txt_mode_blocks.\1."),
    (re.compile(r"^transformer\.single_transformer_blocks\.(\d+)\."), r"diffusion_model.single_blocks.\1."),
]
LAYERS = {"attn.to_q.": "q_proj.", "attn.to_k.": "k_proj.", "attn.to_v.": "v_proj.", "attn.to_out.0.": "attn_out.",
          "ff.linear_in.": "mlp_in.", "ff.linear_out.": "mlp_out."}


def comfy_key(key):
    for pattern, repl in BLOCKS:
        new, n = pattern.subn(repl, key)
        if n:
            break
    else:
        return None
    for old, layer in LAYERS.items():
        i = new.find("." + old)
        if i >= 0:
            return new[:i + 1] + layer + new[i + 1 + len(old):]
    return None


def main(src, dst):
    with safe_open(src, "pt") as f:
        keys = list(f.keys())
        flux3 = any(k.startswith(("transformer.mode_blocks.", "transformer.txt_mode_blocks.",
                                  "transformer.single_transformer_blocks.")) for k in keys)
        if not flux3:
            tmp = dst + ".tmp"
            shutil.copyfile(src, tmp)
            os.replace(tmp, dst)
            print(f"[lora] copied as is: {dst}")
            return
        meta = f.metadata() or {}
        out, skipped = {}, []
        for k in keys:
            new = comfy_key(k)
            if new is None:
                skipped.append(k)
                new = k
            out[new] = f.get_tensor(k)
    tmp = dst + ".tmp"
    save_file(out, tmp, metadata=meta)
    os.replace(tmp, dst)
    print(f"[lora] diffusers FLUX.3 keys -> ComfyUI: {len(keys) - len(skipped)}/{len(keys)} renamed: {dst}")
    for k in skipped[:10]:
        print(f"[lora] WARNING kept unknown key {k}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
