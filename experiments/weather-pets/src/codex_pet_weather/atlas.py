from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image

COLS = 8
ROWS = 9
CELL_WIDTH = 192
CELL_HEIGHT = 208
ATLAS_WIDTH = COLS * CELL_WIDTH
ATLAS_HEIGHT = ROWS * CELL_HEIGHT


ROW_SPECS = {
    "idle": (0, 6),
    "running-right": (1, 8),
    "running-left": (2, 8),
    "waving": (3, 4),
    "jumping": (4, 5),
    "failed": (5, 8),
    "waiting": (6, 6),
    "running": (7, 6),
    "review": (8, 6),
}


@dataclass(frozen=True)
class CellRef:
    state: str
    row: int
    col: int
    used: bool


class AtlasError(ValueError):
    pass


def iter_cells() -> list[CellRef]:
    specs_by_row = {row: (state, used) for state, (row, used) in ROW_SPECS.items()}
    refs: list[CellRef] = []
    for row in range(ROWS):
        state, used_cols = specs_by_row[row]
        for col in range(COLS):
            refs.append(CellRef(state=state, row=row, col=col, used=col < used_cols))
    return refs


def validate_atlas(image: Image.Image) -> None:
    if image.size != (ATLAS_WIDTH, ATLAS_HEIGHT):
        raise AtlasError(
            f"Expected atlas {ATLAS_WIDTH}x{ATLAS_HEIGHT}, got {image.width}x{image.height}"
        )


def load_atlas(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    validate_atlas(image)
    return image


def split_cells(image: Image.Image) -> dict[CellRef, Image.Image]:
    validate_atlas(image)
    cells: dict[CellRef, Image.Image] = {}
    for ref in iter_cells():
        left = ref.col * CELL_WIDTH
        top = ref.row * CELL_HEIGHT
        cells[ref] = image.crop((left, top, left + CELL_WIDTH, top + CELL_HEIGHT))
    return cells


def compose_cells(cells: dict[CellRef, Image.Image]) -> Image.Image:
    out = Image.new("RGBA", (ATLAS_WIDTH, ATLAS_HEIGHT), (0, 0, 0, 0))
    for ref, cell in cells.items():
        if cell.size != (CELL_WIDTH, CELL_HEIGHT):
            raise AtlasError(f"Cell {ref.state}[{ref.col}] has size {cell.size}")
        out.alpha_composite(cell, (ref.col * CELL_WIDTH, ref.row * CELL_HEIGHT))
    return out


def save_atlas(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    suffix = path.suffix.lower()
    if suffix == ".png":
        image.save(path)
    elif suffix == ".webp":
        image.save(path, "WEBP", lossless=True, quality=100, method=6)
    else:
        raise AtlasError("Output path must end in .png or .webp")
