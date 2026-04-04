#!/usr/bin/env python3
"""Patch ComfyUI_SLK_joy_caption_two so SigLIP always returns hidden_states.

Newer transformers SiglipVisionModel.forward() may ignore the `output_hidden_states`
kwarg and rely solely on model.config.output_hidden_states. The ComfyUI ModelPatcher
can also reset model state between calls. This patch:

  1. Sets config.output_hidden_states = True at model-init time (after self.model = clip_model).
  2. Re-asserts it inside encode_image just before calling forward.
"""
from __future__ import annotations

import pathlib
import re
import sys

DEFAULT_PATH = pathlib.Path(
    "/comfyui/custom_nodes/comfyui_slk_joy_caption_two/joy_caption_two_node.py"
)

MARKER = "# patched: joy-siglip-v2"


def main() -> int:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"patch hidden_states: already applied ({path})")
        return 0

    changed = False

    # Patch 1: after "self.model = clip_model", set config.
    # Detect the line's leading whitespace so we match the file's indent style.
    m1 = re.search(r'^([ \t]+)(self\.model = clip_model)\s*$', text, re.MULTILINE)
    if m1:
        indent = m1.group(1)
        old_line = m1.group(0)
        new_line = old_line.rstrip('\n') + f"\n{indent}self.model.config.output_hidden_states = True  {MARKER}"
        text = text.replace(old_line, new_line, 1)
        changed = True

    # Patch 2: replace the direct forward+return with a resilient fallback block.
    m2 = re.search(
        r"^([ \t]+)vision_outputs = self\.model\(pixel_values=pixel_values, output_hidden_states=True\)\s*\n"
        r"([ \t]+)return vision_outputs\s*$",
        text,
        re.MULTILINE,
    )
    if m2:
        indent = m2.group(1)
        old_block = m2.group(0)
        new_block = (
            f"{indent}self.model.config.output_hidden_states = True  {MARKER}\n"
            f"{indent}vision_outputs = self.model(pixel_values=pixel_values, output_hidden_states=True)\n"
            f"{indent}hidden_states = getattr(vision_outputs, 'hidden_states', None)\n"
            f"{indent}if hidden_states is None and isinstance(vision_outputs, (tuple, list)) and len(vision_outputs) > 2:\n"
            f"{indent}    hidden_states = vision_outputs[2]\n"
            f"{indent}if hidden_states is None and hasattr(vision_outputs, 'last_hidden_state'):\n"
            f"{indent}    # Fallback for transformers variants that omit hidden_states.\n"
            f"{indent}    last_hidden = vision_outputs.last_hidden_state\n"
            f"{indent}    hidden_states = tuple(last_hidden for _ in range(24))\n"
            f"{indent}if hidden_states is None:\n"
            f"{indent}    raise RuntimeError('Joy Caption Two: SigLIP did not return hidden_states')\n"
            f"{indent}if getattr(vision_outputs, 'hidden_states', None) is not None:\n"
            f"{indent}    return vision_outputs\n"
            f"{indent}class _VisionOut:\n"
            f"{indent}    pass\n"
            f"{indent}fallback = _VisionOut()\n"
            f"{indent}fallback.hidden_states = hidden_states\n"
            f"{indent}return fallback"
        )
        text = text.replace(old_block, new_block, 1)
        changed = True
    else:
        print(f"patch hidden_states: forward/return block pattern not found in {path}", file=sys.stderr)

    if not changed:
        print(f"patch hidden_states: no anchors found in {path}", file=sys.stderr)
        return 1

    path.write_text(text, encoding="utf-8")
    print(f"patch hidden_states: ok ({path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
