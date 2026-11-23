#!/usr/bin/env python3
"""Render the app icon (light, dark, and tinted variants) into the asset catalog.

    python3 tools/make_app_icon.py

Concept: two ascending bars that resolve into a check mark, for "one requirement at a time".
Ink blue from the design system, no gradients, no glow. Requires Pillow.
"""

from __future__ import annotations

import json
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024
SCALE = 4  # supersample for smooth edges

INK = (0x1F, 0x4E, 0x8C, 255)
INK_DARK_BG = (0x0B, 0x16, 0x26, 255)
INK_LIGHT = (0x7F, 0xA8, 0xE0, 255)
WHITE = (255, 255, 255, 255)


def draw_mark(d: ImageDraw.ImageDraw, color, s: float) -> None:
    """Draw the mark on a canvas of size s (already supersampled)."""
    w = s * 0.105            # stroke and bar width
    r = w / 2
    base = s * 0.70          # common baseline for the bars
    # Two ascending bars.
    bars = [(s * 0.185, s * 0.53), (s * 0.345, s * 0.40)]
    for x, top in bars:
        d.rounded_rectangle([x, top, x + w, base], radius=r, fill=color)
    # Check mark: short stroke down to the baseline, long stroke rising to the top right.
    p1 = (s * 0.525, s * 0.545)
    p2 = (s * 0.610, base - r * 0.15)
    p3 = (s * 0.790, s * 0.270)
    d.line([p1, p2], fill=color, width=int(w), joint="curve")
    d.line([p2, p3], fill=color, width=int(w), joint="curve")
    for (x, y) in (p1, p2, p3):
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def render(background, mark) -> Image.Image:
    s = SIZE * SCALE
    img = Image.new("RGBA", (s, s), background)
    draw_mark(ImageDraw.Draw(img), mark, s)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    light = render(INK, WHITE).convert("RGB")  # App Store icon must be opaque
    dark = render(INK_DARK_BG, INK_LIGHT).convert("RGB")
    tinted = render((0, 0, 0, 255), (235, 235, 235, 255)).convert("L")
    light.save(OUT / "AppIcon.png", optimize=True)
    dark.save(OUT / "AppIcon-Dark.png", optimize=True)
    tinted.save(OUT / "AppIcon-Tinted.png", optimize=True)
    contents = {
        "images": [
            {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}],
             "filename": "AppIcon-Dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}],
             "filename": "AppIcon-Tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (OUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"Wrote icons to {OUT}")


if __name__ == "__main__":
    main()
