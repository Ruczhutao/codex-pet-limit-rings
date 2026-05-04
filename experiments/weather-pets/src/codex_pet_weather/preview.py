from __future__ import annotations

from PIL import Image, ImageDraw, ImageFont

from .atlas import CELL_HEIGHT, CELL_WIDTH, ROW_SPECS, split_cells


def make_contact_sheet(atlas: Image.Image, scale: float = 0.5) -> Image.Image:
    cell_w = max(1, int(CELL_WIDTH * scale))
    cell_h = max(1, int(CELL_HEIGHT * scale))
    label_w = 132
    pad = 8
    header_h = 24
    sheet_w = label_w + pad * 2 + cell_w * 8
    sheet_h = header_h + pad + (cell_h + pad) * len(ROW_SPECS)
    out = Image.new("RGBA", (sheet_w, sheet_h), (248, 248, 246, 255))
    draw = ImageDraw.Draw(out)
    font = ImageFont.load_default()
    draw.text((pad, 6), "Codex Pet Weather Contact Sheet", fill=(20, 24, 30), font=font)
    cells = split_cells(atlas.convert("RGBA"))
    refs = sorted(cells, key=lambda ref: (ref.row, ref.col))
    for state, (row, used_cols) in ROW_SPECS.items():
        y = header_h + pad + row * (cell_h + pad)
        draw.text((pad, y + 8), f"{row}: {state}", fill=(20, 24, 30), font=font)
        draw.text((pad, y + 22), f"{used_cols} frames", fill=(92, 96, 104), font=font)
        for ref in refs:
            if ref.row != row:
                continue
            x = label_w + pad + ref.col * cell_w
            thumb = cells[ref].resize((cell_w, cell_h), Image.Resampling.NEAREST)
            checker = checkerboard((cell_w, cell_h))
            out.alpha_composite(checker, (x, y))
            out.alpha_composite(thumb, (x, y))
            outline = (70, 80, 90, 255) if ref.used else (200, 202, 206, 255)
            draw.rectangle((x, y, x + cell_w - 1, y + cell_h - 1), outline=outline)
    return out.convert("RGB")


def checkerboard(size: tuple[int, int]) -> Image.Image:
    w, h = size
    out = Image.new("RGBA", size, (255, 255, 255, 255))
    draw = ImageDraw.Draw(out)
    tile = 8
    for y in range(0, h, tile):
        for x in range(0, w, tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, min(w, x + tile), min(h, y + tile)), fill=(230, 232, 236, 255))
    return out
