#!/usr/bin/env python3
"""Render the 14-stage rocket atlas on a readable dark preview background."""

import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("atlas", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    atlas = Image.open(args.atlas).convert("RGBA")
    columns, rows = 7, 2
    cell_width, cell_height = atlas.width // columns, atlas.height // rows
    scale = 1.45
    preview_cell = (round(cell_width * scale), round(cell_height * scale) + 28)
    canvas = Image.new("RGB", (preview_cell[0] * columns + 24, preview_cell[1] * rows + 24), (31, 32, 36))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=18)
    for index in range(14):
        column, row = index % columns, index // columns
        cell = atlas.crop((column * cell_width, row * cell_height, (column + 1) * cell_width, (row + 1) * cell_height))
        cell = cell.resize((round(cell_width * scale), round(cell_height * scale)), Image.Resampling.NEAREST)
        x = 12 + column * preview_cell[0]
        y = 12 + row * preview_cell[1]
        tile = Image.new("RGB", preview_cell, (45, 46, 51))
        tile.paste(cell, (0, 0), cell)
        canvas.paste(tile, (x, y))
        label = f"{index + 1}/14"
        box = draw.textbbox((0, 0), label, font=font)
        draw.text((x + (preview_cell[0] - (box[2] - box[0])) / 2, y + preview_cell[1] - 24), label, fill=(245, 245, 247), font=font)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
