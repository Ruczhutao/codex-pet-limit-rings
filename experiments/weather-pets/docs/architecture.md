# Architecture

Codex Pet Weather is a build-time layer system. Codex does not render layers. Codex receives one flattened PNG/WebP atlas.

## Pipeline

```text
source atlas
  -> split into 192x208 cells
  -> derive alpha, silhouette, edge masks
  -> apply weather material to the silhouette
  -> apply atmospheric weather in transparent space
  -> apply Codex-state verb effects by row
  -> apply time-of-day lighting and intensity
  -> reassemble 1536x1872 atlas
  -> write spritesheet.webp and pet.json
```

## Stable Identity

The source avatar supplies the identity layer. The engine preserves the alpha silhouette and uses masks so the same pet remains recognizable. Weather is allowed to change substance, lighting, edge behavior, atmosphere, and damage, but it should not randomly redesign the avatar.

## State Grammar

Rows keep Codex's existing state contract:

| Row | State |
| --- | --- |
| 0 | idle |
| 1 | running-right |
| 2 | running-left |
| 3 | waving |
| 4 | jumping |
| 5 | failed |
| 6 | waiting |
| 7 | running |
| 8 | review |

The renderer uses the work-state row as a verb. Weather decides the material. For example, `failed + rain` should feel like wet rupture; `failed + heat` should feel scorched or warped.

## Weather Model

The weather state is intentionally small:

```json
{
  "condition": "rain",
  "temperature_c": 11.4,
  "precipitation_mm": 0.8,
  "cloud_cover": 91,
  "wind_speed_kmh": 22,
  "wind_direction_deg": 240,
  "humidity": 88,
  "pressure_hpa": 1002,
  "is_day": true,
  "intensity": 0.58
}
```

Different fields drive different layers:

- temperature: color temperature and heat severity
- precipitation: particle density
- cloud cover: contrast and occlusion
- wind speed/direction: slant, shear, lateral streaks
- humidity: fog and condensation strength
- pressure/intensity: instability and damage
- day/night: lighting envelope

## Open-Source Shape

The core library is avatar-agnostic. The demo base exists so new users can try the tool without owning a custom pet. Built-in Codex pets should be copied out as normal atlases and installed as new custom pets; this project should not modify app bundles.
