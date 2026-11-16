#!/usr/bin/env python3
"""Normalize a generated seven-frame strip and replace one row in a 7x6 atlas."""

import argparse
from pathlib import Path
from PIL import Image


def connected_components(image):
    alpha = image.getchannel("A")
    pixels = alpha.load()
    width, height = image.size
    seen = set()
    found = []
    for y in range(height):
        for x in range(width):
            if pixels[x, y] < 24 or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            points = []
            while stack:
                px, py = stack.pop()
                points.append((px, py))
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < width and 0 <= ny < height and pixels[nx, ny] >= 24 and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if len(points) > 2_000:
                found.append((
                    len(points),
                    (min(p[0] for p in points), min(p[1] for p in points),
                     max(p[0] for p in points) + 1, max(p[1] for p in points) + 1),
                ))
    return sorted(found, reverse=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("atlas", type=Path)
    parser.add_argument("strip", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--row", type=int, required=True)
    args = parser.parse_args()

    atlas = Image.open(args.atlas).convert("RGBA")
    strip = Image.open(args.strip).convert("RGBA")
    cell_width, cell_height = 192, 160
    if atlas.size != (cell_width * 7, cell_height * 6):
        raise ValueError(f"Unexpected atlas size: {atlas.size}")
    if not 0 <= args.row < 6:
        raise ValueError("Row must be 0...5")

    normalized = Image.new("RGBA", (cell_width * 7, cell_height), (0, 0, 0, 0))
    components = connected_components(strip)[:7]
    if len(components) != 7:
        raise ValueError(f"Expected seven connected rabbits, found {len(components)}")
    crops = []
    for _, box in sorted(components, key=lambda item: item[1][0]):
        expanded = (
            max(0, box[0] - 5), max(0, box[1] - 5),
            min(strip.width, box[2] + 5), min(strip.height, box[3] + 5),
        )
        crops.append(strip.crop(expanded))
    scale = min((cell_width - 12) / max(x.width for x in crops), (cell_height - 10) / max(x.height for x in crops))
    for column, crop in enumerate(crops):
        pose = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.NEAREST)
        position = (column * cell_width + (cell_width - pose.width) // 2, cell_height - pose.height - 4)
        normalized.alpha_composite(pose, position)

    atlas.paste((0, 0, 0, 0), (0, args.row * cell_height, atlas.width, (args.row + 1) * cell_height))
    atlas.alpha_composite(normalized, (0, args.row * cell_height))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
