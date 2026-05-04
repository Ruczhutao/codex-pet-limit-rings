from __future__ import annotations

import hashlib
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

from .atlas import CELL_HEIGHT, CELL_WIDTH, CellRef, compose_cells, split_cells
from .weather import WeatherState, clamp01


CONDITION_TINTS = {
    "clear": (255, 224, 148),
    "cloud": (164, 174, 184),
    "rain": (88, 142, 194),
    "fog": (204, 214, 216),
    "snow": (226, 239, 250),
    "storm": (82, 92, 128),
    "heat": (255, 178, 78),
    "wind": (154, 210, 215),
}


def weatherize_atlas(base: Image.Image, weather: WeatherState, seed: str | None = None) -> Image.Image:
    cells = split_cells(base.convert("RGBA"))
    rendered = {
        ref: weatherize_cell(ref, cell, weather, seed=seed)
        for ref, cell in cells.items()
    }
    return compose_cells(rendered)


def weatherize_cell(ref: CellRef, cell: Image.Image, weather: WeatherState, seed: str | None = None) -> Image.Image:
    if not ref.used:
        return Image.new("RGBA", cell.size, (0, 0, 0, 0))
    rng = random.Random(cell_seed(ref, weather, seed))
    condition = weather.condition
    intensity = condition_intensity(ref, weather)
    out = cell.convert("RGBA")
    silhouette = out.getchannel("A")
    edge = make_edge_mask(silhouette)

    out = apply_lighting(out, weather, intensity)
    out = apply_material(out, silhouette, edge, weather, intensity, rng)
    out = apply_atmosphere(out, silhouette, weather, intensity, rng, ref)
    out = apply_state_verb(out, silhouette, edge, weather, intensity, rng, ref)
    if condition in {"heat", "wind", "storm"}:
        out = apply_distortion(out, silhouette, weather, intensity, ref)
    return out


def condition_intensity(ref: CellRef, weather: WeatherState) -> float:
    state_boost = {
        "idle": 0.75,
        "running": 1.05,
        "running-right": 1.1,
        "running-left": 1.1,
        "waiting": 1.15,
        "failed": 1.35,
        "review": 0.85,
        "jumping": 1.2,
        "waving": 0.9,
    }.get(ref.state, 1)
    return clamp01(weather.intensity * state_boost)


def apply_lighting(cell: Image.Image, weather: WeatherState, intensity: float) -> Image.Image:
    out = cell.copy()
    temp = clamp01((weather.temperature_c + 10) / 45)
    daylight = 1.0 if weather.is_day else 0.55
    contrast = 1.04 - weather.cloud_cover / 500
    if weather.condition in {"fog", "snow"}:
        contrast -= 0.16 * intensity
    if weather.condition in {"storm", "rain"}:
        daylight -= 0.16 * intensity
    out = ImageEnhance.Brightness(out).enhance(max(0.35, daylight))
    out = ImageEnhance.Contrast(out).enhance(max(0.45, contrast))
    warm = int(255 * temp)
    cool = int(255 * (1 - temp))
    tint = (warm, 210, 170 + cool // 4) if temp >= 0.5 else (165, 204, 255)
    return overlay_color(out, tint, alpha=0.08 + 0.12 * intensity)


def apply_material(
    cell: Image.Image,
    silhouette: Image.Image,
    edge: Image.Image,
    weather: WeatherState,
    intensity: float,
    rng: random.Random,
) -> Image.Image:
    out = cell.copy()
    tint = CONDITION_TINTS[weather.condition]
    alpha = {
        "clear": 0.10,
        "cloud": 0.15,
        "rain": 0.24,
        "fog": 0.22,
        "snow": 0.24,
        "storm": 0.30,
        "heat": 0.24,
        "wind": 0.16,
    }[weather.condition] * (0.45 + intensity)
    out = overlay_color(out, tint, alpha=alpha, mask=silhouette)

    if weather.condition in {"rain", "storm"}:
        out = draw_edge_highlights(out, edge, (178, 228, 255), 0.35 + intensity * 0.45)
    elif weather.condition == "snow":
        out = draw_snow_cap(out, silhouette, edge, intensity, rng)
    elif weather.condition == "fog":
        fog_mask = silhouette.filter(ImageFilter.GaussianBlur(3))
        out = overlay_color(out, (225, 232, 232), alpha=0.28 * intensity + 0.12, mask=fog_mask)
    elif weather.condition == "heat":
        out = draw_edge_highlights(out, edge, (255, 226, 160), 0.30 + intensity * 0.38)
    elif weather.condition == "clear":
        out = draw_edge_highlights(out, edge, (255, 244, 184), 0.16 + intensity * 0.20)
    return out


def apply_atmosphere(
    cell: Image.Image,
    silhouette: Image.Image,
    weather: WeatherState,
    intensity: float,
    rng: random.Random,
    ref: CellRef,
) -> Image.Image:
    out = cell.copy()
    overlay = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    condition = weather.condition
    wind_dx = math.cos(math.radians(weather.wind_direction_deg))
    slant = int((wind_dx if abs(wind_dx) > 0.2 else 0.55) * (7 + weather.wind_speed_kmh / 8))

    if condition in {"rain", "storm"}:
        count = int(18 + 70 * intensity + weather.precipitation_mm * 12)
        color = (155, 215, 255, int(75 + 105 * intensity))
        for _ in range(count):
            x = rng.randint(-25, CELL_WIDTH + 20)
            y = rng.randint(-10, CELL_HEIGHT + 10)
            length = rng.randint(8, 22)
            draw.line((x, y, x + slant, y + length), fill=color, width=1)
    elif condition == "snow":
        count = int(18 + 65 * intensity)
        for _ in range(count):
            x = rng.randint(0, CELL_WIDTH - 1)
            y = rng.randint(0, CELL_HEIGHT - 1)
            r = rng.choice([1, 1, 2])
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(245, 252, 255, rng.randint(80, 170)))
    elif condition == "fog":
        for _ in range(9):
            y = rng.randint(20, CELL_HEIGHT - 15)
            alpha = int(18 + 42 * intensity)
            draw.rounded_rectangle((-10, y, CELL_WIDTH + 10, y + rng.randint(12, 28)), radius=12, fill=(224, 232, 232, alpha))
        overlay = overlay.filter(ImageFilter.GaussianBlur(5))
    elif condition == "storm":
        pass
    elif condition == "wind":
        count = int(8 + 40 * intensity)
        for _ in range(count):
            x = rng.randint(-10, CELL_WIDTH + 10)
            y = rng.randint(0, CELL_HEIGHT)
            draw.line((x, y, x + slant * 2, y + rng.randint(-2, 3)), fill=(205, 238, 238, 80), width=1)

    if not weather.is_day:
        draw.rectangle((0, 0, CELL_WIDTH, CELL_HEIGHT), fill=(18, 28, 48, int(35 + 55 * intensity)))
    if ref.state == "review":
        draw.ellipse((112, 24, 174, 82), fill=(255, 240, 150, int(20 + 50 * (1 - intensity))))
    out.alpha_composite(overlay)
    return out


def apply_state_verb(
    cell: Image.Image,
    silhouette: Image.Image,
    edge: Image.Image,
    weather: WeatherState,
    intensity: float,
    rng: random.Random,
    ref: CellRef,
) -> Image.Image:
    out = cell.copy()
    layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")

    if ref.state == "failed":
        if weather.condition in {"snow", "fog"}:
            color = (230, 245, 255, int(120 + 90 * intensity))
        elif weather.condition in {"heat", "clear"}:
            color = (255, 140, 70, int(120 + 90 * intensity))
        else:
            color = (255, 92, 92, int(120 + 90 * intensity))
        cx = CELL_WIDTH // 2 + rng.randint(-8, 8)
        draw.line((cx - 32, 46, cx - 10, 86, cx - 26, 116, cx + 22, 166), fill=color, width=3)
        draw.line((cx + 25, 52, cx + 5, 94, cx + 18, 126), fill=color, width=2)
    elif ref.state == "waiting":
        alpha = int(60 + 100 * intensity)
        for i in range(3):
            pad = 16 + i * 11 + ref.col % 2
            draw.arc((pad, pad + 8, CELL_WIDTH - pad, CELL_HEIGHT - pad), 218, 318, fill=(255, 230, 148, alpha - i * 18), width=2)
    elif ref.state == "running":
        alpha = int(35 + 90 * intensity)
        for x in range(34, 160, 22):
            draw.line((x, 52, x + rng.randint(-12, 12), 160), fill=(190, 245, 240, alpha), width=2)
    elif ref.state in {"running-left", "running-right"}:
        direction = -1 if ref.state == "running-left" else 1
        alpha = int(42 + 88 * intensity)
        for y in range(44, 168, 20):
            draw.line((92 - direction * 46, y, 92 + direction * 42, y + rng.randint(-4, 4)), fill=(205, 238, 255, alpha), width=2)
    elif ref.state == "jumping":
        draw.ellipse((38, 34, 154, 72), outline=(255, 255, 255, int(80 + 100 * intensity)), width=3)
    elif ref.state == "review":
        draw.rounded_rectangle((40, 150, 152, 166), radius=6, fill=(205, 255, 185, int(70 + 75 * (1 - intensity))))

    out.alpha_composite(layer)
    return out


def apply_distortion(cell: Image.Image, silhouette: Image.Image, weather: WeatherState, intensity: float, ref: CellRef) -> Image.Image:
    if intensity < 0.08:
        return cell
    amp = int(1 + intensity * (3 if weather.condition == "heat" else 2))
    phase = ref.col * 0.9
    src = cell.copy()
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    for y in range(CELL_HEIGHT):
        dx = int(math.sin(y / 13 + phase) * amp)
        row = src.crop((0, y, CELL_WIDTH, y + 1))
        out.alpha_composite(row, (dx, y))
    return out


def make_edge_mask(alpha: Image.Image) -> Image.Image:
    dilated = alpha.filter(ImageFilter.MaxFilter(5))
    eroded = alpha.filter(ImageFilter.MinFilter(5))
    return ImageChops.subtract(dilated, eroded).filter(ImageFilter.GaussianBlur(0.6))


def overlay_color(image: Image.Image, color: tuple[int, int, int], alpha: float, mask: Image.Image | None = None) -> Image.Image:
    alpha_i = int(255 * clamp01(alpha))
    layer = Image.new("RGBA", image.size, (*color, alpha_i))
    if mask is not None:
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    out = image.copy()
    out.alpha_composite(layer)
    return out


def draw_edge_highlights(image: Image.Image, edge: Image.Image, color: tuple[int, int, int], strength: float) -> Image.Image:
    layer = Image.new("RGBA", image.size, (*color, int(255 * clamp01(strength))))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), edge))
    out = image.copy()
    out.alpha_composite(layer)
    return out


def draw_snow_cap(image: Image.Image, silhouette: Image.Image, edge: Image.Image, intensity: float, rng: random.Random) -> Image.Image:
    cap = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(cap)
    alpha_pixels = silhouette.load()
    for x in range(0, CELL_WIDTH, 2):
        top = None
        for y in range(CELL_HEIGHT):
            if alpha_pixels[x, y] > 20:
                top = y
                break
        if top is not None and rng.random() < 0.65:
            height = rng.randint(2, max(3, int(5 + intensity * 9)))
            draw.rectangle((x, top, x + 2, min(CELL_HEIGHT, top + height)), fill=int(100 + intensity * 130))
    cap = cap.filter(ImageFilter.GaussianBlur(0.7))
    layer = Image.new("RGBA", image.size, (245, 252, 255, 0))
    layer.putalpha(ImageChops.lighter(cap, ImageChops.multiply(edge, cap)))
    out = image.copy()
    out.alpha_composite(layer)
    return out


def cell_seed(ref: CellRef, weather: WeatherState, seed: str | None) -> int:
    raw = "|".join(
        [
            seed or "codex-pet-weather",
            ref.state,
            str(ref.row),
            str(ref.col),
            weather.condition,
            f"{weather.temperature_c:.1f}",
            f"{weather.wind_direction_deg:.0f}",
            f"{weather.precipitation_mm:.2f}",
        ]
    )
    return int(hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16], 16)
