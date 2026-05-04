from __future__ import annotations

import json
import math
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class WeatherState:
    source: str
    label: str
    condition: str
    temperature_c: float
    precipitation_mm: float
    cloud_cover: float
    wind_speed_kmh: float
    wind_direction_deg: float
    humidity: float
    pressure_hpa: float
    is_day: bool
    intensity: float
    latitude: float | None = None
    longitude: float | None = None

    def to_json(self) -> dict[str, Any]:
        return asdict(self)


WMO_CONDITIONS = {
    0: "clear",
    1: "clear",
    2: "cloud",
    3: "cloud",
    45: "fog",
    48: "fog",
    51: "rain",
    53: "rain",
    55: "rain",
    56: "rain",
    57: "rain",
    61: "rain",
    63: "rain",
    65: "rain",
    66: "rain",
    67: "rain",
    71: "snow",
    73: "snow",
    75: "snow",
    77: "snow",
    80: "rain",
    81: "rain",
    82: "rain",
    85: "snow",
    86: "snow",
    95: "storm",
    96: "storm",
    99: "storm",
}


def load_weather_json(path: Path) -> WeatherState:
    data = json.loads(path.read_text())
    return WeatherState(**data)


def manual_weather(
    condition: str,
    label: str = "manual",
    temperature_c: float = 12,
    precipitation_mm: float = 0,
    cloud_cover: float = 50,
    wind_speed_kmh: float = 8,
    wind_direction_deg: float = 270,
    humidity: float = 70,
    pressure_hpa: float = 1013,
    is_day: bool = True,
    intensity: float | None = None,
) -> WeatherState:
    condition = normalize_condition(condition)
    inferred = infer_intensity(condition, precipitation_mm, cloud_cover, wind_speed_kmh, humidity, temperature_c)
    return WeatherState(
        source="manual",
        label=label,
        condition=condition,
        temperature_c=temperature_c,
        precipitation_mm=precipitation_mm,
        cloud_cover=cloud_cover,
        wind_speed_kmh=wind_speed_kmh,
        wind_direction_deg=wind_direction_deg,
        humidity=humidity,
        pressure_hpa=pressure_hpa,
        is_day=is_day,
        intensity=inferred if intensity is None else clamp01(intensity),
    )


def fetch_weather(place: str | None, latitude: float | None, longitude: float | None) -> WeatherState:
    if latitude is None or longitude is None:
        if not place:
            raise ValueError("Provide --place or both --lat and --lon")
        latitude, longitude, label = geocode_place(place)
    else:
        label = place or f"{latitude:.3f},{longitude:.3f}"
    params = urllib.parse.urlencode(
        {
            "latitude": latitude,
            "longitude": longitude,
            "current": ",".join(
                [
                    "temperature_2m",
                    "relative_humidity_2m",
                    "precipitation",
                    "weather_code",
                    "cloud_cover",
                    "surface_pressure",
                    "wind_speed_10m",
                    "wind_direction_10m",
                    "is_day",
                ]
            ),
            "timezone": "auto",
        }
    )
    url = f"https://api.open-meteo.com/v1/forecast?{params}"
    data = read_json_url(url)
    current = data["current"]
    code = int(current.get("weather_code", 0))
    condition = normalize_condition(WMO_CONDITIONS.get(code, "cloud"))
    temp = float(current.get("temperature_2m", 12))
    precip = float(current.get("precipitation", 0))
    cloud = float(current.get("cloud_cover", 50))
    wind = float(current.get("wind_speed_10m", 0))
    humidity = float(current.get("relative_humidity_2m", 70))
    pressure = float(current.get("surface_pressure", 1013))
    intensity = infer_intensity(condition, precip, cloud, wind, humidity, temp)
    if temp >= 30 and condition in {"clear", "cloud"}:
        condition = "heat"
        intensity = max(intensity, clamp01((temp - 27) / 12))
    return WeatherState(
        source="open-meteo",
        label=label,
        condition=condition,
        temperature_c=temp,
        precipitation_mm=precip,
        cloud_cover=cloud,
        wind_speed_kmh=wind,
        wind_direction_deg=float(current.get("wind_direction_10m", 270)),
        humidity=humidity,
        pressure_hpa=pressure,
        is_day=bool(current.get("is_day", 1)),
        intensity=intensity,
        latitude=float(latitude),
        longitude=float(longitude),
    )


def geocode_place(place: str) -> tuple[float, float, str]:
    params = urllib.parse.urlencode({"name": place, "count": 1, "language": "en", "format": "json"})
    url = f"https://geocoding-api.open-meteo.com/v1/search?{params}"
    data = read_json_url(url)
    results = data.get("results") or []
    if not results:
        raise ValueError(f"Could not geocode place: {place}")
    hit = results[0]
    parts = [hit.get("name"), hit.get("admin1"), hit.get("country")]
    label = ", ".join(str(part) for part in parts if part)
    return float(hit["latitude"]), float(hit["longitude"]), label


def read_json_url(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": "codex-pet-weather/0.1"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def normalize_condition(condition: str) -> str:
    key = condition.strip().lower().replace("_", "-")
    aliases = {
        "sun": "clear",
        "sunny": "clear",
        "cloudy": "cloud",
        "overcast": "cloud",
        "mist": "fog",
        "drizzle": "rain",
        "thunderstorm": "storm",
        "hot": "heat",
        "windy": "wind",
    }
    key = aliases.get(key, key)
    if key not in {"clear", "cloud", "rain", "fog", "snow", "storm", "heat", "wind"}:
        raise ValueError(f"Unsupported weather condition: {condition}")
    return key


def infer_intensity(
    condition: str,
    precipitation_mm: float,
    cloud_cover: float,
    wind_speed_kmh: float,
    humidity: float,
    temperature_c: float,
) -> float:
    if condition == "clear":
        return clamp01((100 - cloud_cover) / 100)
    if condition == "cloud":
        return clamp01(cloud_cover / 100)
    if condition == "rain":
        return clamp01(precipitation_mm / 4 + wind_speed_kmh / 80)
    if condition == "fog":
        return clamp01(humidity / 100 * 0.7 + cloud_cover / 300)
    if condition == "snow":
        return clamp01(precipitation_mm / 3 + (0 - temperature_c) / 20)
    if condition == "storm":
        return clamp01(0.55 + precipitation_mm / 8 + wind_speed_kmh / 100)
    if condition == "heat":
        return clamp01((temperature_c - 26) / 14 + (100 - cloud_cover) / 300)
    if condition == "wind":
        return clamp01(wind_speed_kmh / 65)
    return 0.5


def clamp01(value: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return max(0.0, min(1.0, value))
