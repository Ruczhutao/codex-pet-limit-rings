from __future__ import annotations

import math

from PIL import Image, ImageDraw, ImageFilter

from .atlas import CELL_HEIGHT, CELL_WIDTH, CellRef, compose_cells, iter_cells


STATE_COLORS = {
    "idle": (132, 180, 205),
    "running-right": (112, 198, 224),
    "running-left": (112, 198, 224),
    "waving": (180, 170, 238),
    "jumping": (246, 180, 105),
    "failed": (230, 92, 86),
    "waiting": (238, 192, 88),
    "running": (92, 205, 170),
    "review": (120, 215, 132),
}


def make_demo_atlas() -> Image.Image:
    cells = {ref: draw_demo_cell(ref) for ref in iter_cells()}
    return compose_cells(cells)


def draw_demo_cell(ref: CellRef) -> Image.Image:
    cell = Image.new("RGBA", (CELL_WIDTH, CELL_HEIGHT), (0, 0, 0, 0))
    if not ref.used:
        return cell
    draw = ImageDraw.Draw(cell, "RGBA")
    t = ref.col / max(1, 7)
    base = STATE_COLORS[ref.state]
    cx = CELL_WIDTH // 2 + state_offset_x(ref.state, ref.col)
    cy = CELL_HEIGHT // 2 + state_offset_y(ref.state, ref.col)

    # Outer glass bulb.
    w = 78 + int(4 * math.sin(t * math.tau))
    h = 98 + int(5 * math.cos(t * math.tau))
    bbox = (cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2)
    glow = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow, "RGBA")
    gdraw.ellipse(expand(bbox, 8), fill=(*base, 38))
    glow = glow.filter(ImageFilter.GaussianBlur(7))
    cell.alpha_composite(glow)

    draw.ellipse(bbox, fill=(*base, 78), outline=(18, 24, 31, 230), width=4)
    draw.ellipse(contract(bbox, 9), outline=(255, 255, 255, 76), width=2)
    draw.arc(contract(bbox, 18), start=205, end=324, fill=(255, 255, 255, 128), width=3)

    # Base and stem keep identity stable across rows.
    stem_top = bbox[3] - 6
    draw.rounded_rectangle((cx - 21, stem_top, cx + 21, stem_top + 24), radius=8, fill=(30, 36, 42, 230))
    draw.rounded_rectangle((cx - 31, stem_top + 20, cx + 31, stem_top + 34), radius=6, fill=(17, 22, 28, 235))

    # Internal instrument line changes with row/column but remains abstract.
    for i in range(3):
        phase = t * math.tau + i * 2.1
        x1 = cx - 24 + i * 24
        y1 = cy + int(math.sin(phase) * 20)
        x2 = x1 + 18
        y2 = cy + int(math.cos(phase) * 18)
        draw.line((x1, y1, x2, y2), fill=(255, 255, 255, 145), width=2)
        draw.ellipse((x2 - 3, y2 - 3, x2 + 3, y2 + 3), fill=(255, 255, 255, 170))

    if ref.state == "failed":
        draw.line((cx - 24, cy - 32, cx - 4, cy - 8, cx - 15, cy + 22, cx + 18, cy + 40), fill=(40, 0, 0, 210), width=3)
    elif ref.state == "waiting":
        draw.arc((cx - 35, cy - 42, cx + 35, cy + 42), start=270, end=42 + ref.col * 12, fill=(255, 255, 255, 160), width=3)
    elif ref.state == "review":
        draw.rounded_rectangle((cx - 28, cy + 10, cx + 28, cy + 24), radius=5, fill=(255, 255, 255, 150))
    elif ref.state == "jumping":
        draw.ellipse((cx - 16, cy - 50, cx + 16, cy - 38), fill=(255, 255, 255, 120))

    return cell


def state_offset_x(state: str, col: int) -> int:
    if state == "running-right":
        return int(-12 + col * 3.5)
    if state == "running-left":
        return int(12 - col * 3.5)
    if state == "running":
        return int(math.sin(col * math.tau / 6) * 5)
    return 0


def state_offset_y(state: str, col: int) -> int:
    if state == "jumping":
        return -int(math.sin(col / 4 * math.pi) * 28)
    if state == "waving":
        return int(math.sin(col * math.tau / 4) * 4)
    if state == "failed":
        return min(12, col * 2)
    return int(math.sin(col * math.tau / 6) * 3)


def expand(box: tuple[int, int, int, int], amount: int) -> tuple[int, int, int, int]:
    left, top, right, bottom = box
    return left - amount, top - amount, right + amount, bottom + amount


def contract(box: tuple[int, int, int, int], amount: int) -> tuple[int, int, int, int]:
    left, top, right, bottom = box
    return left + amount, top + amount, right - amount, bottom - amount
