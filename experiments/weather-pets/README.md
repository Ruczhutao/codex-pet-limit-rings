# Weather Pets Experiment

This folder contains the earlier `codex-pet-weather` renderer. It is a Python experiment for turning a normal Codex pet spritesheet into weather-mutated variants while keeping Codex's custom-pet atlas contract intact.

It lives here so the main repository can stay focused on `codex-pet-limit-rings`, while preserving the broader idea behind the exploration: Codex pets can become ambient interfaces for context, limits, work state, weather, and mood.

## Local Development

```bash
python3 -m pip install -e .
python3 -m pytest
```

## Example

```bash
python3 -m codex_pet_weather install --place London --pet-name weather-daemon
```

Only redistribute atlases you own or have permission to share.
