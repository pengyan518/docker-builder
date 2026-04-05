#!/usr/bin/env python3
"""Patch ComfyUI_SLK_joy_caption_two LLM loader for newer transformers.

Some transformers/peft/quantization combinations fail when Joy passes
`device_map=self.load_device` directly into `from_pretrained` for the LoRA-adapted
LLM. This patch removes that argument and moves the model explicitly after load.
"""
from __future__ import annotations

import pathlib
import re
import sys

DEFAULT_PATH = pathlib.Path(
    "/comfyui/custom_nodes/comfyui_slk_joy_caption_two/joy_caption_two_node.py"
)

MARKER = "# patched: joy-llm-loader-v1"


def main() -> int:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"patch llm_loader: already applied ({path})")
        return 0

    changed = False

    # Remove device_map=self.load_device from from_pretrained calls.
    pattern = re.compile(r"^([ \t]*)device_map=self\.load_device,\s*$", re.MULTILINE)
    matches = pattern.findall(text)
    if matches:
        text = pattern.sub("", text)
        changed = True

    # Ensure models are moved explicitly to requested device before eval().
    eval_pattern = re.compile(r"^([ \t]*)text_model\.eval\(\)\s*$", re.MULTILINE)
    eval_matches = list(eval_pattern.finditer(text))
    if eval_matches:
        text = eval_pattern.sub(
            r"\1text_model.to(self.load_device)  " + MARKER + "\n\\g<0>",
            text,
            count=2,
        )
        changed = True

    if not changed:
        print(f"patch llm_loader: no expected patterns found in {path}", file=sys.stderr)
        return 1

    path.write_text(text, encoding="utf-8")
    print(f"patch llm_loader: ok ({path}), removed device_map lines={len(matches)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
