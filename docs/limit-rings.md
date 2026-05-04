# Codex Pet Limit Rings

Codex Pet Limit Rings is a native macOS companion app for Codex pets. It does not patch Codex, replace pet art, or modify the Codex app bundle. It follows the current pet with a transparent always-on-top window and exposes its own menu-bar icon.

The overlay is pet-agnostic. It works with any pet Codex displays because the app tracks the pet window bounds rather than reading, editing, or understanding the pet artwork.

## Display Modes

Three mutually exclusive display modes are available via **Settings** (⌘,):

- **Rings** — Two concentric rings around the pet. Outer ring = short-window limit. Inner ring = weekly limit. Colors shift from green/blue (healthy) through amber to red (critical).
- **Bars** — Horizontal progress bars directly beneath the pet, showing the same two limits with percentage labels.
- **Minimal** — Compact numeric readout (`72%  45%`) floating at the top-right corner of the pet.

## Settings Panel

Open from the menu bar icon: **Settings…** (⌘,)

| Setting | Options | Default |
|---------|---------|---------|
| **Color Scheme** | Warm / Cool / Cyberpunk / Original | Warm |
| **Tracking Speed** | Fast (~30fps) / Medium (~12fps) / Smooth (~8fps) | Fast |
| **Display Mode** | Rings / Bars / Minimal | Rings |
| **Data Source** | Both / Short Window / Weekly | Both |
| **Readout Mode** | Always / Hover | Always |
| **Language** | 中文 / English | 中文 |

### Readout Mode

- **Always** — Numerical values are always visible (ring labels, bar percentages, minimal numbers).
- **Hover** — Values appear only when the cursor is over the pet or the overlay. Rings show arc-endpoint labels; bars show percentages; minimal mode is not affected (it is inherently minimal).

### Data Source

- **Both** — Shows both short-window and weekly limits.
- **Short Window** — Shows only the short-window limit.
- **Weekly** — Shows only the weekly limit.

When a single source is selected, the bar height and minimal width auto-shrink to fit one item.

## Experience Contract

- A rings icon appears in the macOS menu bar.
- `Show Rings` toggles the overlay without quitting the app.
- `Refresh Now` rereads usage and pet-position state.
- Closing the Codex pet hides the overlay.
- Multi-display positioning uses the screen containing the pet bounds, not the currently focused screen.
- Switching to another Codex pet requires no extra setup; the overlay follows the active pet.
- Dragging the pet makes the overlay follow the gesture immediately while Codex persists the new position.

## Data Flow

The app reads live usage first, then local files as support or fallback:

- `https://chatgpt.com/backend-api/wham/usage`: live usage endpoint, called with the local ChatGPT access token from `~/.codex/auth.json`.
- `~/.codex/auth.json`: local ChatGPT auth token used for the live usage call.
- `~/.codex/.codex-global-state.json`: current pet bounds, using `electron-avatar-overlay-bounds.mascot`.
- `electron-avatar-overlay-open` in the same state file: whether the Codex pet is currently open.
- `~/.codex/logs_2.sqlite`: fallback source using the newest `codex.rate_limits` event when the live usage call fails.

No OpenAI API key is required. The menu summary says `Live` when the direct usage read succeeds and `Cached` when it is showing the local event-log fallback.

## Rendering Model

- Colors are derived from remaining capacity and the selected color scheme.
- Exact percentages respect the **Readout Mode** setting (always-on or hover-only).
- Additional model-limit buckets may appear as small outer markers in rings mode when available.

## Install Contract

`tools/install-limit-rings.sh` builds:

```text
~/Applications/CodexPetLimitRings.app
```

and installs:

```text
~/Library/LaunchAgents/com.codex-pet.limit-rings.plist
```

The LaunchAgent starts the app at login. The installer also removes the earlier prototype app and LaunchAgent names if present:

```text
~/Applications/CodexLimitAura.app
~/Library/LaunchAgents/com.codex-pet.limit-aura.plist
```

`tools/uninstall-limit-rings.sh` unloads the LaunchAgent, removes the app bundle, clears saved preferences, and also cleans up those earlier prototype names.

## Development

Build and run the app from the repository:

```bash
tools/run-limit-rings.sh
```

Render a static preview:

```bash
swiftc tools/codex-pet-limit-rings.swift -o tmp/codex-pet-limit-rings -framework AppKit -lsqlite3
tmp/codex-pet-limit-rings --preview tmp/limit-rings-preview.png --size 164
```

## Codex Skill

The repository includes a skill at `skills/codex-pet-limit-rings/`. Copy that folder into `~/.codex/skills/` or run `tools/install-codex-skill.sh` to make Codex auto-discover the workflow in future sessions.

The skill intentionally points agents at the companion-app boundary and validation commands. It should not encourage app-bundle patching as the default path.
