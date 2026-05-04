from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from PIL import Image

from .atlas import ATLAS_HEIGHT, ATLAS_WIDTH, AtlasError, load_atlas, save_atlas, validate_atlas
from .demo import make_demo_atlas
from .effects import weatherize_atlas
from .preview import make_contact_sheet
from .weather import WeatherState, fetch_weather, load_weather_json, manual_weather


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (AtlasError, OSError, ValueError) as exc:
        parser.exit(1, f"codex-pet-weather: error: {exc}\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="codex-pet-weather",
        description="Weatherize Codex custom pet spritesheets without patching Codex.",
    )
    sub = parser.add_subparsers(required=True)

    render = sub.add_parser("render", help="Render a weatherized atlas")
    add_common_render_args(render)
    render.add_argument("--output", required=True, type=Path, help="Output .webp or .png atlas path")
    render.add_argument("--state-output", type=Path, help="Optional weather-state.json output path")
    render.set_defaults(func=cmd_render)

    install = sub.add_parser("install", help="Render and install into CODEX_HOME/pets/<pet-name>")
    add_common_render_args(install)
    install.add_argument("--pet-name", default="weather-daemon", help="Folder/id slug for the installed pet")
    install.add_argument("--display-name", default="Weather Daemon", help="Display name in Codex settings")
    install.add_argument(
        "--description",
        default="A Codex pet possessed by local weather.",
        help="Description shown in Codex settings",
    )
    install.add_argument("--codex-home", type=Path, default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")))
    install.set_defaults(func=cmd_install)

    validate = sub.add_parser("validate", help="Validate atlas dimensions")
    validate.add_argument("atlas", type=Path)
    validate.set_defaults(func=cmd_validate)

    contact = sub.add_parser("contact-sheet", help="Render a QA contact sheet for an atlas")
    contact.add_argument("atlas", type=Path)
    contact.add_argument("--output", required=True, type=Path)
    contact.add_argument("--scale", type=float, default=0.5)
    contact.set_defaults(func=cmd_contact_sheet)

    demo = sub.add_parser("demo-base", help="Write the built-in demo base atlas")
    demo.add_argument("--output", required=True, type=Path)
    demo.set_defaults(func=cmd_demo_base)
    return parser


def add_common_render_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--source", type=Path, help="Existing 1536x1872 Codex pet atlas. Omit for demo base.")
    parser.add_argument("--place", help="Place name to geocode with Open-Meteo, e.g. London")
    parser.add_argument("--lat", type=float, help="Latitude")
    parser.add_argument("--lon", type=float, help="Longitude")
    parser.add_argument("--weather-json", type=Path, help="Use a saved weather-state.json instead of live weather")
    parser.add_argument(
        "--condition",
        help="Manual condition for offline rendering: clear, cloud, rain, fog, snow, storm, heat, wind",
    )
    parser.add_argument("--temperature-c", type=float, default=12)
    parser.add_argument("--precipitation-mm", type=float, default=0)
    parser.add_argument("--cloud-cover", type=float, default=50)
    parser.add_argument("--wind-speed-kmh", type=float, default=8)
    parser.add_argument("--wind-direction-deg", type=float, default=270)
    parser.add_argument("--humidity", type=float, default=70)
    parser.add_argument("--pressure-hpa", type=float, default=1013)
    parser.add_argument("--night", action="store_true", help="Manual weather is night-time")
    parser.add_argument("--intensity", type=float, help="Override inferred weather intensity, 0..1")
    parser.add_argument("--seed", help="Stable seed for deterministic particles")


def cmd_render(args: argparse.Namespace) -> int:
    base = load_source(args.source)
    weather = resolve_weather(args)
    out = weatherize_atlas(base, weather, seed=args.seed)
    save_atlas(out, args.output)
    if args.state_output:
        write_json(args.state_output, weather.to_json())
    print(f"Rendered {args.output} using {weather.condition} weather for {weather.label}")
    return 0


def cmd_install(args: argparse.Namespace) -> int:
    pet_name = slugify(args.pet_name)
    pet_dir = args.codex_home / "pets" / pet_name
    base = load_source(args.source)
    weather = resolve_weather(args)
    out = weatherize_atlas(base, weather, seed=args.seed or pet_name)
    save_atlas(out, pet_dir / "spritesheet.webp")
    write_json(
        pet_dir / "pet.json",
        {
            "id": pet_name,
            "displayName": args.display_name,
            "description": args.description,
            "spritesheetPath": "spritesheet.webp",
        },
    )
    write_json(pet_dir / "weather-state.json", weather.to_json())
    print(f"Installed {args.display_name} at {pet_dir}")
    print("Open Codex Settings > Appearance > Pets, refresh custom pets, then select it.")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    image = Image.open(args.atlas).convert("RGBA")
    validate_atlas(image)
    print(f"OK: {args.atlas} is {ATLAS_WIDTH}x{ATLAS_HEIGHT}")
    return 0


def cmd_contact_sheet(args: argparse.Namespace) -> int:
    atlas = load_atlas(args.atlas)
    sheet = make_contact_sheet(atlas, scale=args.scale)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    print(f"Wrote contact sheet to {args.output}")
    return 0


def cmd_demo_base(args: argparse.Namespace) -> int:
    save_atlas(make_demo_atlas(), args.output)
    print(f"Wrote demo base atlas to {args.output}")
    return 0


def load_source(source: Path | None) -> Image.Image:
    if source is None:
        return make_demo_atlas()
    return load_atlas(source)


def resolve_weather(args: argparse.Namespace) -> WeatherState:
    provided = [args.weather_json is not None, args.condition is not None, args.place is not None or args.lat is not None or args.lon is not None]
    if sum(bool(item) for item in provided) > 1:
        raise ValueError("Use only one weather source: --weather-json, --condition, or live --place/--lat/--lon")
    if args.weather_json:
        return load_weather_json(args.weather_json)
    if args.condition:
        return manual_weather(
            args.condition,
            label="manual",
            temperature_c=args.temperature_c,
            precipitation_mm=args.precipitation_mm,
            cloud_cover=args.cloud_cover,
            wind_speed_kmh=args.wind_speed_kmh,
            wind_direction_deg=args.wind_direction_deg,
            humidity=args.humidity,
            pressure_hpa=args.pressure_hpa,
            is_day=not args.night,
            intensity=args.intensity,
        )
    return fetch_weather(args.place, args.lat, args.lon)


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def slugify(value: str) -> str:
    chars = []
    previous_dash = False
    for char in value.strip().lower():
        if char.isalnum():
            chars.append(char)
            previous_dash = False
        elif not previous_dash:
            chars.append("-")
            previous_dash = True
    slug = "".join(chars).strip("-")
    if not slug:
        raise ValueError("Pet name must contain at least one alphanumeric character")
    return slug
