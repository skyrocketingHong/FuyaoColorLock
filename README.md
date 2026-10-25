<p align="center">
  English | <a href="README_ZH.md">简体中文</a>
</p>

<h1 align="center">Fuyao Color Lock</h1>

<p align="center">
  A native macOS menu-bar utility for inspecting and applying external display connection formats.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?logo=macos" alt="macOS 13.0 or later">
  <img src="https://img.shields.io/badge/version-1.0-4F6B00" alt="Version 1.0">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
</p>

Fuyao Color Lock reads live system connection modes and can request a supported format change through the native display API. The panel separates live mode information, driver-advertised capabilities and older macOS configuration records.

**Only native modes compatible with the current resolution, refresh rate, HDR state and VRR state can be applied.** Other modes remain view-only. A successful action requires repeated system readback matching the requested mode; it is not an independent measurement of HDMI output or panel gamut. The app does not change ICC profiles or automatically reapply a mode after waking.

## Features

- A native popover with a fixed canvas and internal scrolling. Switching displays does not resize the panel to fit a different number of modes.
- Separate display timing, macOS records and driver capabilities. Missing and conflicting information stays explicit.
- Explicit connection-format changes using `CADisplay`, with native 64-bit mode IDs and readback confirmation. No BetterDisplay installation is required.
- Read-only refresh after display changes, wake and periodic polling. Opening the app or selecting a display does not reconfigure the connection.
- English and Simplified Chinese resources, system appearance and native controls.
- A native RGB preference section with EDID change previews, export, administrator-authorized installation and restoration of the original override. Installation is followed by manual reconnection and output verification.

## Requirements and build

Apple Silicon, macOS 13.0 or later, and an installed Xcode toolchain selected through `xcode-select` or `DEVELOPER_DIR`. The native app has no third-party dependencies and does not need Python. Python 3 is needed only for the optional command-line EDID tool and its tests.

From this checkout:

```bash
scripts/build-app.sh
open build/FuyaoColorLock.app
```

The script packages an optimized arm64 app with localization resources and verifies its ad hoc signature before replacing the previous build. The app is not notarized. Build 2 retains marketing version 1.0.

## Reading the panel

| Information | Meaning |
| --- | --- |
| Live connection | The current native system mode, including timing, format, range, bit depth and reported gamut. |
| macOS record | Saved WindowServer fields. Records may be absent, old or conflicting; they are not live measurements. |
| Mode options | Native modes compatible with the current timing offer Apply when the setter is available. Other timings and driver-only entries remain view-only. |
| Previous target | An unresolved numeric ID saved by an older version. Driver IDs can change; it is not converted into a guessed color format. |
| Refresh | Reads the catalog and saved records again without switching modes. |

Choose **Apply** beside a compatible mode. A brief blank screen can occur during link negotiation. The panel reports the request as pending until readback confirms the mode, or explicitly leaves it unconfirmed. Unsupported choices cannot be clicked. Clearing a legacy preference does not change the display. Driver timing and colorimetry are never guessed when unavailable or undecoded.

## Optional EDID override

In the panel, select a display and open **Prefer RGB with EDID override**:

- **Export** saves a plist without changing the system.
- **Install** previews the change, asks for confirmation and uses the macOS administrator prompt. It preserves existing plist fields and backs up the original file before installing the modified EDID.
- **Restore** restores the original file byte-for-byte, or removes the app's override if none existed before. External changes cause restoration to stop rather than overwrite them.

Overrides are scoped by vendor and product IDs, so they can affect multiple displays of the same model. The app reports file installation separately from live output. Reconnect after installing or restoring. Full RGB still requires hardware verification. This is an OS-level override, not a write to the display's EEPROM.

The optional command-line equivalent generates a file only:

```bash
python3 scripts/patch-edid.py --name "Your display name" --outdir build/edid-override
```

This generates a file and prints installation instructions; it does not install anything. An unavailable display or invalid EDID causes an error instead of a patch. Inspect the file before following the printed privileged installation command, and back up any existing override at that path first. Reconnect the display after installation. To roll back, restore the backup or remove only the newly installed override, then reconnect.

The patch clears CTA YCbCr 4:4:4 and 4:2:2 flags and removes CTA YCbCr 4:2:0 video and capability-map blocks, preserving other extensions and detailed timings. It **does not select** a bit depth, Full Range, SDR, HDR, sRGB or P3. Driver behavior and advertisements outside the patched fields can still affect the negotiated link. Verify the result on the connected display.

## Architecture and validation

SwiftUI renders the panel in an AppKit `NSPopover`. CoreGraphics enumerates displays; IORegistry supplies timing tables and EDID data. SkyLight and CoreDisplay associate displays with framebuffers and saved records. QuartzCore's private `CADisplay` and `CADisplayMode` provide native live modes and the setting path. Runtime ABI checks and fresh mode enumeration guard every request; unsupported APIs leave the options view-only. See [the implementation evidence](docs/PRIVATE_DISPLAY_API.md).

```text
Sources/FuyaoColorLock/   Catalog, state, settings and native panel
Resources/               Bundle metadata and localized strings
scripts/build-app.sh      Optimized local app packaging
scripts/test-models.sh    Offline display-model regression tests
scripts/test.sh           All offline regression checks
scripts/patch-edid.py     Optional EDID override generator
Tests/                   Offline regression fixtures and assertions
```

See [VALIDATION.md](docs/VALIDATION.md) for checks and remaining manual acceptance steps.

## Privacy

Display information and preferences stay local. The app reads IORegistry, CoreGraphics and saved WindowServer records. It does not send display identifiers. EDID export and installation occur only after an explicit action; macOS handles administrator credentials. Managed originals are stored beside the override directory in `.FuyaoColorLock` for restoration.

## License

MIT.

---

This project was developed with assistance from generative AI.

<a href="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg">
  <img src="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg" alt="Vibe PR" width="220">
</a>
