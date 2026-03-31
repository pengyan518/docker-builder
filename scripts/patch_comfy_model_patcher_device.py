#!/usr/bin/env python3
"""Patch ComfyUI comfy/model_patcher.py for Hugging Face SigLIP (Joy Caption Two).

Transformers' SiglipVisionTransformer exposes ``device`` as a read-only property.
ModelPatcher still does ``self.model.device = ...`` after ``.to()``; that raises
AttributeError on newer torch/transformers. We replace those assignments with a
helper that catches AttributeError/TypeError (parameters are already moved by .to()).
"""
from __future__ import annotations

import pathlib
import sys

DEFAULT_PATH = pathlib.Path("/comfyui/comfy/model_patcher.py")

HELPER = """def _comfy_safe_set_model_device(model, device):
    \"\"\"HF vision models may use a read-only .device; ComfyUI assigns after .to().\"\"\"
    try:
        model.device = device
    except (AttributeError, TypeError):
        pass


"""


def main() -> int:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    text = path.read_text(encoding="utf-8")
    if "_comfy_safe_set_model_device" in text:
        print(f"patch model_patcher: already applied ({path})")
        return 0

    c_off = text.count("self.model.device = offload_device")
    c_to = text.count("self.model.device = device_to")
    if c_off == 0 and c_to == 0:
        print(f"patch model_patcher: expected assignments not found in {path}", file=sys.stderr)
        return 1

    anchor = "import comfy_aimdo.model_vbar\n\n"
    if anchor in text:
        text = text.replace(anchor, anchor + HELPER, 1)
    else:
        insert_at = "\nclass ModelPatcher:"
        if insert_at not in text:
            print(
                f"patch model_patcher: cannot insert helper (no comfy_aimdo anchor, no {insert_at!r}) in {path}",
                file=sys.stderr,
            )
            return 1
        text = text.replace(insert_at, "\n\n" + HELPER + "class ModelPatcher:", 1)

    text = text.replace("self.model.device = offload_device", "_comfy_safe_set_model_device(self.model, offload_device)")
    text = text.replace("self.model.device = device_to", "_comfy_safe_set_model_device(self.model, device_to)")

    path.write_text(text, encoding="utf-8")
    print(
        f"patch model_patcher: ok ({path}) replaced offload_device×{c_off}, device_to×{c_to}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
