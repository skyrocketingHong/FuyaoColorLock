<p align="center">
  English | <a href="README_ZH.md">简体中文</a>
</p>

<h1 align="center">FuyaoColorLock</h1>

<p align="center">
  A lightweight macOS menu-bar utility that locks an external display's connection color mode (pixel format) and re-applies it automatically through the free BetterDisplay CLI
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?logo=macos" alt="macOS 13.0 or later">
  <img src="https://img.shields.io/badge/version-1.0-4F6B00" alt="Version 1.0">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
</p>

macOS keeps resetting external displays from the pixel format you picked (for example 8-bit SDR RGB Full Range) back to YCbCr or 10-bit variants after waking from sleep, reconnecting, or display link renegotiation. BetterDisplay can switch the mode for free, but the feature that keeps it locked — Configuration Protection — is a Pro feature.

FuyaoColorLock closes exactly that gap: it watches display reconfiguration, wake, and mode-change events, and whenever the target display drifts away from the pinned color mode, it re-applies it through the BetterDisplay CLI that ships with the free version. On the test machine a forced switch away from the pinned mode was corrected in about 4–6 seconds.

## Features

- Locks the connection color mode of one external display (8/10-bit, RGB or YCbCr chroma, Full/Limited range presets)
- Reacts to display reconfiguration callbacks, wake events, and manual mode changes (2.5 s debounce), plus a 15 s safety poll
- Menu-bar status with current mode, display picker, mode picker, and one-click re-apply
- Optional Launch at Login
- Ships `patch-edid.py`, an optional one-time EDID override generator that strips YCbCr capability from the display so macOS stops offering YCbCr modes at all

## Requirements

- macOS 13.0 or later (built and tested on Apple Silicon)
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) (free version is enough), installed at `/Applications/BetterDisplay.app` and running — the CLI needs the app's local connection

## Quick start

```bash
git clone <this repo>
cd FuyaoColorLock
scripts/build-app.sh
open build/FuyaoColorLock.app
```

Click the menu-bar lock icon, pick the display (for example *Redmi 27 NU*) and the target mode (for example *8-bit SDR RGB Full Range*). The lock starts working immediately; verify by switching the mode away in BetterDisplay and watching it snap back within seconds.

## How it works

- **Enumerating modes**: the connection color mode list exposed by BetterDisplay corresponds to the `TimingElements → ColorModes` tables published by the display driver in IORegistry (`IOMobileFramebufferShim`).
- **Reading and setting**: the free BetterDisplay CLI supports `get -connectionMode` / `set -connectionMode="bpc:8+range:full+encoding:rgb"`, which FuyaoColorLock wraps with a timeout and retry.
- **Locking**: `CGDisplayRegisterReconfigurationCallback`, `NSWorkspace` wake notifications, and a low-frequency poll each trigger a check that compares the live mode description against the pinned preset and re-applies it when they diverge.

## Optional: remove YCbCr modes entirely (EDID override)

If you would rather make YCbCr unreachable than correct it, generate a patched EDID override from the display's live EDID:

```bash
python3 scripts/patch-edid.py --name "Redmi 27 NU" --outdir build/edid-override
```

The script clears the CEA-861 YCbCr 4:4:4 / 4:2:2 capability bits and any YCbCr 4:2:0 capability map block, fixes the checksum, and prints the exact `sudo` commands to install the override into `/Library/Displays/Contents/Resources/Overrides/`. After installing, unplug and replug the display (or reboot). To revert, delete the override file and replug again.

Notes: install/uninstall require admin rights and a replug; some 4:2:0 modes can come from driver-side sources the EDID does not control — keep the menu-bar lock enabled as the precise, always-on guarantee.

## Project structure

```
Sources/FuyaoColorLock/   Swift sources (CLI wrapper, guard, menu-bar UI)
scripts/build-app.sh      builds build/FuyaoColorLock.app (resolves tools via xcrun)
scripts/patch-edid.py     optional EDID override generator
Resources/Info.plist      bundle metadata (LSUIElement menu-bar app)
```

## Privacy

No network access, no sandbox, no accessibility permissions. All operations are local: the BetterDisplay CLI and IORegistry reads.

## License

MIT. FuyaoColorLock is an independent tool and is not affiliated with BetterDisplay; it only drives the BetterDisplay CLI installed on your machine.

---

This project was developed with assistance from generative AI.

<a href="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg">
  <img src="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg" alt="Vibe PR" width="220">
</a>
