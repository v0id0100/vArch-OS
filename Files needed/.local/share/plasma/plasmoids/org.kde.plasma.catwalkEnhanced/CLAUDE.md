# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A KDE Plasma 6 plasmoid (widget) written in QML. It displays an animated cat that walks faster as CPU usage rises, alongside an optional CPU percentage label and temperature readout. Enhanced fork of the original CatWalk by Yuri Saurov. Current version: **1.3**.

Plugin ID: `org.kde.plasma.catwalkEnhanced`

## Install / test cycle

```bash
# Install from local folder
plasmapkg2 -i /path/to/Bettter-CatWalk-Plasmoid/

# Restart Plasma to pick up changes
kquitapp6 plasmashell && kstart6 plasmashell

# Uninstall
plasmapkg2 -r org.kde.plasma.catwalkEnhanced
```

There is no build step for QML — changes to `.qml` files take effect after reinstalling and restarting Plasmashell.

## Build translations

```bash
cd translations && ./build.sh
```

Requires `gettext` (`msgfmt`). Compiles `.po` files into `.mo` binaries under `contents/locale/<lang>/LC_MESSAGES/`.

## Architecture

### Data flow

`main.qml` → `CompactRepresentation.qml` (all visuals live here)

- `main.qml` is a thin `PlasmoidItem` shell. It detects panel vs. desktop placement and panel orientation (`inPanel`, `isVertical`), adds a "Open System Monitor" context menu action, and delegates rendering to `CompactRepresentation`.
- `CompactRepresentation.qml` owns everything visual: layout, sizing, cat animation, CPU sensor.

### Sensors

Two `Sensors.Sensor` instances with `enabled` guards to stop unnecessary ksysguard polling:

- `totalSensor` (`cpu/all/usage`) — enabled only when cat or CPU text is visible.
- `tempSensor` (user-configured sensor ID) — enabled only when temperature display or angry mode is active.

### Animation

`totalSensor` drives the cat animation. A `Timer` cycles through 5 active frames or holds on the idle frame when CPU is below the idle threshold. Timer interval formula: `Math.ceil(5000 / Math.sqrt(cpu + 35) - 400)` — lower CPU = slower animation.

Two precomputed path arrays control which assets are used:
- `imagePaths` — normal frames: `my-idle-symbolic.svg`, `my-active-{0-4}-symbolic.svg`
- `angryImagePaths` — angry frames: same idle, `my-active-{0-4}-symbolic_angry.svg`

The timer picks the active array based on `isAngry`; no logic is duplicated.

### Layout system

A single `GridLayout` handles both orientations. The visible elements (cat, CPU text, temperature) form a **sequence** computed at runtime from `displayType` and `showTemp`. Dividers are injected between elements when `showDivider` is true. Each cell gets its `Layout.row`/`Layout.column` from its index in the sequence, so visibility, order, and divider count all flow naturally.

- **Horizontal** (`useVertical = false`): 1 row, N columns (up to 5: item + divider + item + divider + item). Swapping with `cfg_swapOrder` reverses the sequence.
- **Vertical** (`useVertical = true`): 1 column, N rows.

Divider cells use `Rectangle` (not a Label `|`). They collapse to zero size when `showDivider` is false. In vertical mode the divider cell includes 10px of built-in padding (`dividerBlockHeight = dividerThickness + 10`) so no extra margins are needed.

#### Vertical layout sizing

`grid.height = useVertical ? totalMinHeight : compactRepresentation.height` — must use `totalMinHeight` (not `compactRepresentation.height`) to avoid a feedback loop where Plasma's stale allocated height was reused for `rowSpacing` auto calculation.

#### Spacing

`cfg_customSpacing` stores the per-column-gap in pixels, or `-1` for auto mode.

- **Auto** (`customSpacing = -1`): `columnSpacing` fills available widget width divided equally across the two column gaps. `grid.width = compactRepresentation.width`.
- **Fixed**: `columnSpacing = customSpacing`. `grid.width` shrinks to the natural content size; `anchors.centerIn: parent` centers it. Spacing stays constant as the widget is resized.

### Temperature display

When `showTemp` is true, a temperature label is shown alongside (or instead of) the cat and CPU text. The value comes from `tempSensor` and is formatted by `formatTemp()` into °C, °F, or K based on `tempUnit`. The label uses the same color-coded thresholds as the CPU label (neutral ≥ 70°C, negative ≥ 85°C).

`tempBoxWidth` is derived from `TextMetrics` on the live `tempText` string (temperature changes slowly, so no jitter). `tempScaleFactor` controls its font size independently (or linked via `linkScales`).

### Angry cat

When `tempSensor` reads ≥ `angryTemp` and `angryEnabled` is true, `isAngry` becomes `true`. This switches the animation to the `_angry` SVG variants (`my-active-{0-4}-symbolic_angry.svg`).

- Threshold `0` → always angry regardless of sensor value (useful for testing).
- Threshold `> 0` → angry when sensor reports ≥ threshold (sensor returning `0` = not connected will never trigger).
- `angryEnabled = false` → angry mode fully disabled regardless of temperature.

**SVG theming:** the angry SVGs use `fill:currentColor` + `class="ColorScheme-Text"` + a `<defs id="defs3051">` CSS block — same pattern as the normal frames — so they follow Plasma's dynamic color scheme automatically.

**Colorization:** `KSvg.SvgItem` (id: `catSvg`) has `layer.enabled: isAngry` and `layer.effect: MultiEffect` (from `import QtQuick.Effects`). As temperature climbs above the threshold, `colorization` ramps from `0.20` → `0.95` and `colorizationColor` shifts from yellow → orange → red over a 50°C range above `angryTemp`. Both properties animate with a 500ms `Behavior`.

The temperature sensor is shared between the temperature display and angry mode. If either is active, `tempSensor` polls; if both are off, polling stops entirely.

Temperature sensor IDs are hardware-specific. The config UI shows a live reading (via a `previewSensor` gated on active temp features) so users can verify their sensor ID immediately.

### Configuration

- Schema: `contents/config/main.xml` (KConfig XML)
- Config UI: `contents/ui/config/ConfigGeneral.qml`
- Config model: `contents/config/config.qml`

Config keys:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `idle` | Int | 0 | CPU % below which cat shows idle frame |
| `type` | Int | 0 | Cat/CPU visibility: 0=cat+CPU, 1=cat only, 2=CPU only, 3=neither (use with `showTemp`) |
| `updateRateLimit` | Int | 1000 | CPU sensor poll interval (ms) |
| `catScale` | Double | 1.0 | Cat size multiplier |
| `textScale` | Double | 1.0 | CPU text size multiplier |
| `tempScale` | Double | 1.0 | Temperature text size multiplier |
| `dividerScale` | Double | 1.0 | Divider length multiplier |
| `dividerThickness` | Int | 2 | Divider line thickness in px |
| `linkScales` | Bool | true | Keep cat, CPU text, temperature and divider sizes in sync |
| `textBelowCat` | Bool | false | Vertical stacked layout (text below cat) |
| `swapOrder` | Bool | false | Swap element order |
| `showDivider` | Bool | false | Show divider line between elements |
| `customSpacing` | Int | -1 | Gap between items in px; -1 = auto (fill width) |
| `showTemp` | Bool | false | Show temperature readout |
| `tempUnit` | Int | 0 | Temperature unit: 0=°C, 1=°F, 2=K |
| `tempSensorId` | String | `cpu/cpu0/temperature` | KSysGuard sensor ID for temperature |
| `tempUpdateRate` | Int | 5000 | Temperature sensor poll interval (ms) |
| `angryEnabled` | Bool | true | Enable angry cat mode |
| `angryTemp` | Int | 80 | Temperature threshold in °C for angry mode (0 = always angry) |
