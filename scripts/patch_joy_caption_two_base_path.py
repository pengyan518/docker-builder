#!/usr/bin/env python3
"""Patch ComfyUI_SLK_joy_caption_two to find Joy weights on RunPod volume when CMD bypasses start_with_runpod_volume.sh.

Joy node uses folder_paths.models_dir (/comfyui/models) only; extra_model_paths.yaml does not map
Joy_caption_two. If the container starts with `python main.py` instead of the image CMD, no symlink
is created and clip_model.pt is missing under /comfyui/models/Joy_caption_two.
"""
from __future__ import annotations

import pathlib
import re
import sys

TARGET = pathlib.Path(
    "/comfyui/custom_nodes/comfyui_slk_joy_caption_two/joy_caption_two_node.py"
)

OLD = re.compile(
    r"^BASE_MODEL_PATH = Path\(folder_paths\.models_dir, \"Joy_caption_two\"\)\s*$",
    re.MULTILINE,
)

NEW = '''def _joy_caption_two_base_path() -> Path:
    """Prefer Comfy models dir; if clip_model.pt is on volume only, use that path."""
    primary = Path(folder_paths.models_dir, "Joy_caption_two")
    if (primary / "clip_model.pt").exists():
        return primary
    import os
    for root in (
        Path(os.environ.get("RUNPOD_VOLUME_PATH", "/workspace")) / "models" / "Joy_caption_two",
        Path("/runpod-volume/models/Joy_caption_two"),
    ):
        if (root / "clip_model.pt").exists():
            return root
    return primary


BASE_MODEL_PATH = _joy_caption_two_base_path()'''


def main() -> int:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else TARGET
    text = path.read_text(encoding="utf-8")
    if "_joy_caption_two_base_path" in text:
        print(f"patch: already applied ({path})")
        return 0
    if not OLD.search(text):
        print(f"patch: pattern not found in {path}", file=sys.stderr)
        return 1
    path.write_text(OLD.sub(NEW, text, count=1), encoding="utf-8")
    print(f"patch: wrote BASE_MODEL_PATH fallback ({path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
