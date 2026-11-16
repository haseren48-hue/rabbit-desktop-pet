#!/usr/bin/env python3
"""Deterministic geometry/color repairs for the expedition sprite atlases."""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "RabbitDesktopPet" / "Resources"


def add_astronaut_padding() -> None:
    path = RESOURCES / "rabbit-astronaut-atlas.png"
    backup = ROOT / "work" / "asset-backups" / "rabbit-astronaut-atlas.png"
    source = Image.open(backup if backup.exists() else path).convert("RGBA")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    cell_width, cell_height = 192, 160

    for row in range(6):
        for column in range(7):
            left, top = column * cell_width, row * cell_height
            cell = complete_cross_row_sprite(source, row, column)
            output.alpha_composite(cell, (left, top))

    output.save(path)


def alpha_components(image: Image.Image) -> list[list[tuple[int, int]]]:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    width, height = image.size
    visited: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []

    for y in range(height):
        for x in range(width):
            if pixels[x, y] < 12 or (x, y) in visited:
                continue
            stack = [(x, y)]
            visited.add((x, y))
            component: list[tuple[int, int]] = []
            while stack:
                current_x, current_y = stack.pop()
                component.append((current_x, current_y))
                for neighbor in (
                    (current_x + 1, current_y),
                    (current_x - 1, current_y),
                    (current_x, current_y + 1),
                    (current_x, current_y - 1),
                ):
                    neighbor_x, neighbor_y = neighbor
                    if not (0 <= neighbor_x < width and 0 <= neighbor_y < height):
                        continue
                    if neighbor in visited or pixels[neighbor_x, neighbor_y] < 12:
                        continue
                    visited.add(neighbor)
                    stack.append(neighbor)
            components.append(component)

    return components


def keep_largest_alpha_component(image: Image.Image) -> Image.Image:
    """Remove sprite fragments duplicated from the previous atlas row."""
    components = alpha_components(image)

    if not components:
        return image
    keep = set(max(components, key=len))
    cleaned = Image.new("RGBA", image.size, (0, 0, 0, 0))
    source_pixels = image.load()
    target_pixels = cleaned.load()
    for x, y in keep:
        target_pixels[x, y] = source_pixels[x, y]
    return cleaned


def complete_cross_row_sprite(source: Image.Image, row: int, column: int) -> Image.Image:
    """Recover feet crossing the first three row boundaries, then remove row spill."""
    cell_width, cell_height = 192, 160
    left, top = column * cell_width, row * cell_height
    cell = source.crop((left, top, left + cell_width, top + cell_height))
    main = keep_largest_alpha_component(cell)
    assembled = Image.new("RGBA", (cell_width, cell_height + 40), (0, 0, 0, 0))
    assembled.alpha_composite(main)

    # Rows 0-2 were exported across a row boundary: the torso ends at the
    # current cell bottom and its boots continue at the next cell top. Rows
    # 3-5 already contain complete boots, so their next-row fragments are only
    # duplicates and must not be appended.
    if row < 3:
        next_top = (row + 1) * cell_height
        next_cell = source.crop((
            left,
            next_top,
            left + cell_width,
            next_top + cell_height,
        ))
        source_pixels = next_cell.load()
        overflow = Image.new("RGBA", next_cell.size, (0, 0, 0, 0))
        overflow_pixels = overflow.load()
        boot_cutoff = (0, 14, 7)[row]
        for component in alpha_components(next_cell):
            xs = [point[0] for point in component]
            ys = [point[1] for point in component]
            # Overflow boots begin within the first eight pixels and finish
            # before the next rabbit's ears/head. Ignore tiny antialias flecks.
            if min(ys) > 8 or max(ys) >= 35 or len(component) < 150:
                continue
            for x, y in component:
                # Row 1's overflow also includes a duplicated horizontal hem;
                # retain only the boots/lower continuation below that seam.
                if y >= boot_cutoff:
                    overflow_pixels[x, y] = source_pixels[x, y]
        overflow_bounds = overflow.getchannel("A").getbbox()
        main_bounds = main.getchannel("A").getbbox()
        if overflow_bounds and main_bounds:
            boots = overflow.crop(overflow_bounds)
            assembled.alpha_composite(boots, (
                overflow_bounds[0],
                main_bounds[3] - 2,
            ))

    bounds = assembled.getchannel("A").getbbox()
    if not bounds:
        return Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
    sprite = assembled.crop(bounds)
    scale = min(1.0, 132 / sprite.height, 116 / sprite.width)
    size = (
        max(1, round(sprite.width * scale)),
        max(1, round(sprite.height * scale)),
    )
    sprite = sprite.resize(size, Image.Resampling.NEAREST)
    normalized = Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
    normalized.alpha_composite(sprite, (
        (cell_width - sprite.width) // 2,
        (cell_height - sprite.height) // 2,
    ))
    return normalized


def deepen_progressive_soot() -> None:
    path = RESOURCES / "rabbit-charred-recovery-atlas.png"
    backup = ROOT / "work" / "asset-backups" / "rabbit-charred-recovery-atlas.png"
    source = Image.open(backup if backup.exists() else path).convert("RGBA")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    cell_width, cell_height = 192, 160
    soot_strength = [0.78, 0.68, 0.57, 0.45, 0.32, 0.18, 0.06]

    for row in range(6):
        for column, strength in enumerate(soot_strength):
            left, top = column * cell_width, row * cell_height
            cell = complete_cross_row_sprite(source, row, column)
            pixels = list(cell.get_flattened_data())
            darkened = []
            for index, (red, green, blue, alpha) in enumerate(pixels):
                if alpha == 0:
                    darkened.append((0, 0, 0, 0))
                    continue
                x = index % cell_width
                y = index // cell_width
                # Coarse, deterministic soot variation keeps the result visibly pixel-like.
                fleck = 0.11 if ((x // 5) * 3 + (y // 5) * 5 + row * 7 + column) % 13 < 3 else 0
                amount = min(0.9, strength + fleck)
                darkened.append((
                    round(red * (1 - amount) + 12 * amount),
                    round(green * (1 - amount) + 11 * amount),
                    round(blue * (1 - amount) + 10 * amount),
                    alpha,
                ))
            cell.putdata(darkened)
            output.alpha_composite(cell, (left, top))

    output.save(path)


def restore_missing_rocket_fins() -> None:
    path = RESOURCES / "rocket-construction-atlas.png"
    backup = ROOT / "work" / "asset-backups" / "rocket-construction-atlas.png"
    atlas = Image.open(backup if backup.exists() else path).convert("RGBA")
    cell_width, cell_height = 126, 190
    donor_left = 4 * cell_width
    donor = atlas.crop((donor_left, 0, donor_left + cell_width, cell_height))

    # Stage 5 already has the approved left/right red fins. Copy just those side regions
    # behind the taller stage 6 and 7 bodies, retaining their exact palette and outline.
    left_fin = donor.crop((18, 124, 45, 188))
    right_fin = donor.crop((81, 124, 108, 188))
    for stage in (6, 7):
        cell_left = (stage - 1) * cell_width
        cell = atlas.crop((cell_left, 0, cell_left + cell_width, cell_height))
        repaired = Image.new("RGBA", cell.size, (0, 0, 0, 0))
        repaired.alpha_composite(left_fin, (18, 124))
        repaired.alpha_composite(right_fin, (81, 124))
        repaired.alpha_composite(cell)
        atlas.paste(repaired, (cell_left, 0))

    atlas.save(path)


if __name__ == "__main__":
    add_astronaut_padding()
    deepen_progressive_soot()
    restore_missing_rocket_fins()
