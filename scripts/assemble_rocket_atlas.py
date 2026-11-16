#!/usr/bin/env python3
"""Normalize a generated 7x2 rocket construction sheet at one consistent scale."""

import argparse
from pathlib import Path
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGBA")
    columns, rows = 7, 2
    cell_width, cell_height = 126, 190
    crops = []
    for row in range(rows):
        for column in range(columns):
            slot = source.crop((
                round(column * source.width / columns),
                round(row * source.height / rows),
                round((column + 1) * source.width / columns),
                round((row + 1) * source.height / rows),
            ))
            box = slot.getchannel("A").getbbox()
            if box is None:
                raise ValueError(f"Empty cell at row {row}, column {column}")
            crops.append(slot.crop(box))

    scale = min(
        (cell_width - 10) / max(crop.width for crop in crops),
        (cell_height - 8) / max(crop.height for crop in crops),
    )
    atlas = Image.new("RGBA", (cell_width * columns, cell_height * rows), (0, 0, 0, 0))
    for index, crop in enumerate(crops):
        pose = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.NEAREST)
        column = index % columns
        row = index // columns
        position = (
            column * cell_width + (cell_width - pose.width) // 2,
            row * cell_height + cell_height - pose.height - 4,
        )
        atlas.alpha_composite(pose, position)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
