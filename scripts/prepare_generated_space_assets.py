#!/usr/bin/env python3
"""Normalize ImageGen moon/explosion artwork into app-ready pixel assets."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "work" / "imagegen"
RESOURCES = ROOT / "Sources" / "RabbitDesktopPet" / "Resources"


def alpha_bbox(image: Image.Image, threshold: int = 10) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A").point(lambda value: 255 if value > threshold else 0)
    box = alpha.getbbox()
    if box is None:
        raise ValueError("asset has no visible pixels")
    return box


def prepare_moon() -> Path:
    source = Image.open(WORK / "moon-transparent.png").convert("RGBA")
    left, top, right, bottom = alpha_bbox(source)
    pad = max(right - left, bottom - top) // 40
    crop = source.crop((max(0, left - pad), max(0, top - pad), min(source.width, right + pad), min(source.height, bottom + pad)))

    side = max(crop.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
    final = square.resize((144, 144), Image.Resampling.NEAREST)
    output = RESOURCES / "pixel-moon-detailed.png"
    final.save(output, optimize=True)
    return output


def prepare_explosion() -> Path:
    source = Image.open(WORK / "explosion-transparent.png").convert("RGBA")
    # The generated artwork is a precise 4 x 2 sheet. Resizing the complete
    # canvas keeps the intentionally increasing/decreasing blast size intact.
    final = source.resize((640, 320), Image.Resampling.NEAREST)
    output = RESOURCES / "pixel-explosion-atlas.png"
    final.save(output, optimize=True)
    return output


if __name__ == "__main__":
    for asset in (prepare_moon(), prepare_explosion()):
        print(asset)
