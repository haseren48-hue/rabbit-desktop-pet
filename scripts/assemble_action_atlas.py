#!/usr/bin/env python3
"""Normalize a generated 6x7 transparent rabbit atlas into fixed runtime cells."""

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def components(image: Image.Image):
    alpha = image.getchannel("A")
    pixels = alpha.load()
    width, height = image.size
    seen = set()
    found = []
    for y in range(height):
        for x in range(width):
            if pixels[x, y] < 24 or (x, y) in seen:
                continue
            queue = [(x, y)]
            seen.add((x, y))
            points = []
            while queue:
                px, py = queue.pop()
                points.append((px, py))
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < width and 0 <= ny < height and pixels[nx, ny] >= 24 and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        queue.append((nx, ny))
            if len(points) > 2_000:
                found.append((
                    len(points),
                    (min(p[0] for p in points), min(p[1] for p in points),
                     max(p[0] for p in points) + 1, max(p[1] for p in points) + 1),
                ))
    return sorted(found, reverse=True)[:42]


def cluster_rows(found):
    centers = sorted((box[1] + box[3]) / 2 for _, box in found)
    seeds = [centers[min(len(centers) - 1, row * 7 + 3)] for row in range(6)]
    for _ in range(20):
        rows = [[] for _ in range(6)]
        for item in found:
            box = item[1]
            center = (box[1] + box[3]) / 2
            row = min(range(6), key=lambda i: abs(center - seeds[i]))
            rows[row].append(item)
        if all(len(row) == 7 for row in rows):
            return rows
        for index, row in enumerate(rows):
            if row:
                seeds[index] = sum((b[1] + b[3]) / 2 for _, b in row) / len(row)
    raise ValueError(f"Expected seven poses per row, got {[len(row) for row in rows]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fixed-grid", action="store_true")
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGBA")
    if args.fixed_grid:
        rows = None
    else:
        rows = cluster_rows(components(source))
    cell_width, cell_height = 192, 160
    atlas = Image.new("RGBA", (cell_width * 7, cell_height * 6), (0, 0, 0, 0))

    for row_index in range(6):
        crops = []
        if args.fixed_grid:
            for column in range(7):
                slot = source.crop((
                    round(column * source.width / 7), round(row_index * source.height / 6),
                    round((column + 1) * source.width / 7), round((row_index + 1) * source.height / 6),
                ))
                box = slot.getchannel("A").getbbox()
                if box is None:
                    raise ValueError(f"Empty grid cell at row {row_index}, column {column}")
                crops.append(slot.crop(box))
        else:
            for _, box in sorted(rows[row_index], key=lambda item: item[1][0]):
                expanded = (
                    max(0, box[0] - 5), max(0, box[1] - 5),
                    min(source.width, box[2] + 5), min(source.height, box[3] + 5),
                )
                crops.append(source.crop(expanded))
        scale = min(
            (cell_width - 12) / max(crop.width for crop in crops),
            (cell_height - 10) / max(crop.height for crop in crops),
        )
        for column, crop in enumerate(crops):
            size = (round(crop.width * scale), round(crop.height * scale))
            pose = crop.resize(size, Image.Resampling.NEAREST)
            position = (
                column * cell_width + (cell_width - pose.width) // 2,
                row_index * cell_height + cell_height - pose.height - 4,
            )
            atlas.alpha_composite(pose, position)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
