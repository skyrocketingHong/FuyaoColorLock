<p align="center">
  English | <a href="README_ZH.md">简体中文</a>
</p>

<h1 align="center">Fuyao Color Lock</h1>

<p align="center">
  A zero-dependency macOS menu-bar utility that shows each external display's real connection color modes and locks them in place with an optional EDID override
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?logo=macos" alt="macOS 13.0 or later">
  <img src="https://img.shields.io/badge/version-1.0-4F6B00" alt="Version 1.0">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
</p>

macOS keeps resetting external displays from the pixel format you picked (for example 8-bit SDR RGB Full Range) back to YCbCr or 10-bit variants after waking from sleep or a link renegotiation. BetterDisplay can switch the mode, but keeping it locked is a Pro feature, and its switching path is closed-source.

Fuyao Color Lock takes a fully independent approach:

- **Read side**: the driver publishes every display's timing table (`TimingElements → ColorModes`, with bit depth, RGB/YCbCr chroma, range, EOTF) in IORegistry. The app reads it directly and shows, per display tab, exactly the modes that display actually supports — no hardcoded list.
- **Lock side**: the companion `patch-edid.py` script generates a one-time EDID override that strips YCbCr capability from the display. Once installed, macOS cannot pick YCbCr modes at all, on any reset, with no background process required. The app watches display events and re-detects displays (`SLSDetectDisplays`) after each reconnect or wake while a lock is enabled.

## Requirements

- macOS 13.0 or later (built and verified on Apple Silicon, macOS 27)
- No third-party apps. BetterDisplay is not needed (and can be uninstalled).

## Quick start

```bash
git clone <this repo>
cd FuyaoColorLock
scripts/build-app.sh
open build/FuyaoColorLock.app
```

The menu-bar panel opens with one tab per external display. Each tab shows the active timing and the color modes the driver actually offers on it (top row = driver preference, nothing preselected), plus an independent lock toggle. Selecting a mode pins it and enables that display's lock; after display events the app re-detects displays to nudge mode selection back into bounds.

### Locking out YCbCr for good

```bash
python3 scripts/patch-edid.py --name "Redmi 27 NU" --outdir build/edid-override
```

The script patches the live EDID (clears CEA-861 YCbCr 4:4:4/4:2:2 bits and any 4:2:0 capability map, fixes checksums) and prints the exact `sudo` commands to install the override into `/Library/Displays/Contents/Resources/Overrides/`. Unplug and replug the display afterwards. To revert, delete the file and replug.

## How it works

- Display enumeration pairs CG online displays with their framebuffer shim via `SLSCopyDisplayInfoDictionary`'s `IODisplayLocation` (controller segment like `disp0@…`); names come from CoreDisplay's info dictionary.
- Color mode fields were verified against BetterDisplay's own list on macOS 27: `PixelEncoding` 0=RGB / 2=YCbCr 4:2:0 / 3=4:4:4 / 6=4:2:2, `DynamicRange` 1=Full / 0=Limited, `EOTF` 0=SDR / 2=HDR10; `DPTimingModeId` identifies the active timing.
- What the app deliberately does **not** do: writing the connection mode directly. That path lives in a closed-source IOKit channel (verified: it is not the CGS display-mode API, not IORegistry properties, and not the `SLSDisplay*Preset` family). The EDID override plus event-driven re-detection achieves the lock without it.

## Project structure

```
Sources/FuyaoColorLock/   Swift sources (catalog, guard, menu-bar UI, SLS bridges)
scripts/build-app.sh      builds build/FuyaoColorLock.app (resolves tools via xcrun)
scripts/patch-edid.py     EDID override generator (strip YCbCr)
Resources/Info.plist      bundle metadata (LSUIElement menu-bar app)
```

## Privacy

No network access, no sandbox, no accessibility permissions. Everything is local IORegistry/CoreGraphics reads plus the optional EDID override you install yourself.

## License

MIT.

---

This project was developed with assistance from generative AI.

<a href="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg">
  <img src="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg" alt="Vibe PR" width="220">
</a>
