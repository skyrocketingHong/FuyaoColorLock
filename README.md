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

**Only native modes compatible with the current resolution, refresh rate, HDR state and VRR state can be applied.** Other modes remain view-only. A successful action requires repeated system readback matching the requested mode; it is not an independent measurement of HDMI output or panel gamut. The app does not change ICC profiles. Automatic restoration requires explicitly enabling the mode lock for that display.

## Features

- A native popover with a fixed canvas and internal scrolling. Switching displays does not resize the panel to fit a different number of modes.
- Opening the menu-bar icon on an external display automatically shows that display. A secondary menu lets you inspect another display without changing any mode.
- Separate display timing, macOS records and driver capabilities. Missing and conflicting information stays explicit.
- Explicit connection-format changes using `CADisplay`, with native 64-bit mode IDs and readback confirmation. No BetterDisplay installation is required.
- Per-display mode locking after explicit opt-in. Display changes, wake and periodic checks can restore the saved format while preserving the current timing; unlocked displays remain read-only during refresh.
- English and Simplified Chinese resources, system appearance and native controls.
- A native RGB preference section with EDID change previews, export, administrator-authorized installation and restoration of the original override. Installation is followed by manual reconnection and output verification.

## Requirements and build

Apple Silicon, macOS 13.0 or later, and an installed Xcode toolchain selected through `xcode-select` or `DEVELOPER_DIR`. The native app has no third-party dependencies and does not need Python. Python 3 is needed only for the optional command-line EDID tool and its tests.

From this checkout:

```bash
scripts/build-app.sh
open build/FuyaoColorLock.app
```

The script uses the selected SDK through `xcrun` (validated with macOS 27.2 and Swift 6.4.2), packages an optimized arm64 app with localization resources and verifies its ad hoc signature before replacing the previous build. Native macOS 26 and 27 controls are used where available, with macOS 13 fallbacks. The app is not notarized. Build 6 retains marketing version 1.0.

## Reading the panel

Click the app's menu-bar icon on the display you want to inspect. Each opening selects that screen by its system display ID. To inspect another display, use **Other displays** (the two-display icon at the top right). A manual selection stays in place while the panel is open; the next opening follows its source screen again.

If the source cannot be matched uniquely, including mirrored or unsupported built-in screens, the panel asks for a selection instead of showing an unrelated display. Choosing a display only changes the information being shown.

| Information | Meaning |
| --- | --- |
| Color mode | The current native system mode, including timing, format, range, bit depth and reported gamut. |
| macOS record | Saved WindowServer fields. Records may be absent, old or conflicting; they are not live measurements. |
| Switch mode | Other compatible native formats offer Apply when the setter is available. The current format is shown once in the summary; other timings and driver-only entries remain view-only. |
| Previous target | An unresolved numeric ID saved by an older version. Driver IDs can change; it is not converted into a guessed color format. |
| Refresh | Reads the current state and checks enabled locks. Only an explicitly enabled lock may restore its saved mode. |

Choose **Apply** beside a compatible mode. A brief blank screen can occur during link negotiation. The panel reports the request as pending until readback confirms the mode, or explicitly leaves it unconfirmed. Unsupported choices cannot be clicked. Clearing a legacy preference does not change the display. Driver timing and colorimetry are never guessed when unavailable or undecoded.

## Mode lock

The panel is ordered **color mode switching and lock → installation configuration → app settings and About**. The lock switch is in the first section, alongside the live connection information and mode choices.

1. Apply the desired compatible mode and check that system readback confirms it.
2. Enable **Lock color mode**. When the current mode matches, the summary already shows the locked target. During a mismatch or waiting state, expand **Locked target** to inspect it. Each display has an independent lock, disabled by default; old numeric target preferences do not silently enable it.
3. Keep the app running. After wake, reconnection or detected drift, it looks for a unique current native mode matching the saved parameters, restores it when compatible and verifies the result. Changing driver mode IDs after reconnection does not change the saved target.
4. A confirmed manual mode change while locked updates the locked target. To stop automatic restoration, turn off the switch; this does not itself change the current mode. Use **Launch at Login** in **Application settings** if the app should resume monitoring after login.

A different resolution, refresh rate, HDR or VRR state suspends restoration rather than forcing the old timing. Missing data, disconnected displays and sleeping screens remain waiting or unavailable. Failed restoration retries after 5 and 15 seconds, then pauses after three consecutive failures; a continuous recovery cycle also limits automatic setting requests to three per 60 seconds. Confirmed recovery from sleep, session unavailability or a display disconnection starts a new bounded automatic cycle. A failed catalog read or temporary disappearance during the app's own mode change does not renew that budget. A pause caused by an unconfirmed manual change is preserved until you retry or change the lock. Inspect the live mode before choosing **Retry** in the lock section. An enabled switch means the preference is active, while the adjacent status explains whether the system mode actually matches.

After the screen turns back on, **Waiting for the display and session…** is a temporary readiness state. The app checks actual display power and session availability instead of relying on a single wake notification, then revisits driver readiness for a bounded period. A missed or out-of-order notification must not leave the lock permanently marked as sleeping. Unknown readings do not authorize a write, and the saved timing constraints are unchanged.

While a lock is enabled, lightweight checks read its connection and the display topology every second, including after a long stay on the lock screen. Native display-change events also trigger discovery. Full EDID and driver catalogs refresh every 20 seconds or when a change is detected; repeated events do not postpone an already scheduled restoration. System readiness, retry backoff and readback confirmation still determine when restoration can finish.

## Optional EDID override

Below the mode controls, **Installation configuration** contains the **Prefer RGB** action:

- **Export**, inside **Configuration details**, saves a plist without changing the system. The same disclosure contains change counts and the file location.
- **Install** previews the change, asks for confirmation and uses the macOS administrator prompt. It preserves existing plist fields and backs up the original file before installing the modified EDID.
- **Restore** restores the original file byte-for-byte, or removes the app's override if none existed before. External changes cause restoration to stop rather than overwrite them.

Overrides are scoped by vendor and product IDs, so they can affect multiple displays of the same model. The app reports file installation separately from live output. Reconnect after installing or restoring. Full RGB still requires hardware verification. This is an OS-level override, not a write to the display's EEPROM.

The optional command-line equivalent generates a file only:

```bash
python3 scripts/patch-edid.py --name "Your display name" --outdir build/edid-override
```

This generates a file and prints installation instructions; it does not install anything. An unavailable display or invalid EDID causes an error instead of a patch. Inspect the file before following the printed privileged installation command, and back up any existing override at that path first. Reconnect the display after installation. To roll back, restore the backup or remove only the newly installed override, then reconnect.

The patch clears CTA YCbCr 4:4:4 and 4:2:2 flags and removes CTA YCbCr 4:2:0 video and capability-map blocks, preserving other extensions and detailed timings. It **does not select** a bit depth, Full Range, SDR, HDR, sRGB or P3. Driver behavior and advertisements outside the patched fields can still affect the negotiated link. Verify the result on the connected display.

**Application settings** and **About** follow installation configuration in the panel. Login startup uses the system service, and About opens the standard macOS panel with the application's actual version and copyright information.

## Manually verify a change

### Check the live mode after applying a format

1. Open the menu-bar icon on the intended display and check the display name at the top. Note the **Color mode** summary before changing anything, so you can select the previous compatible mode again if needed.
2. In **Switch mode**, apply a listed RGB Full format. Check `RGB Full` on the format line and the bit depth, HDR and gamut below it, for example `8-bit · SDR · sRGB`. `sRGB` alone does not establish the encoding or range. Compatible rows share the timing shown in the summary; resolution, refresh rate, HDR and VRR state should remain unchanged.
3. Allow several seconds for **Confirmed by system read-back.** The app requires two complete matching reads 0.5 seconds apart, with a six-second verification window. **Not confirmed** is not a success result.
4. Click the **Refresh** arrow icon at the top right or press **⌘R**. Expand **Display details** to check that **Last read** advances, and check that **Color mode** still shows the requested format. If it shows `YCbCr` or `RGB Limited`, the current system mode does not meet the RGB Full target. If the live mode is unavailable, the result remains unverified.
5. To check whether the result survives renegotiation, repeat the read after sleep/wake or after reconnecting the HDMI cable. For the lock-screen case, wait until the screen actually powers down, then wake and unlock it; allow the readiness state to finish. With the lock off, this checks what macOS retained. With the lock on, also check **Locked target** and the lock status: restoration must finish with the live mode matching the target. Merely staying in the same mode does not exercise the restoration path. Turn off the lock when you want to inspect negotiation without automatic correction.

If wake restoration remains pending, the following read-only command shows the app's recent lifecycle and recovery events. It records state changes and outcomes without display names, UUIDs or EDID contents:

```bash
/usr/bin/log show --last 10m --info --style compact \
  --predicate 'process == "FuyaoColorLock" AND subsystem == "ing.fuyaoskyrocket.FuyaoColorLock" AND category == "ModeLock"'
```

Look for sleep/wake hints, readiness changes, recovery confirmation and paused attempts. No output may mean no relevant event occurred in that interval or an older build is running. The command does not change display settings and needs no cleanup.

The driver mode list and **macOS record** are reference data, not the current-mode verdict. A **Current** label identifies the system-reported mode, not a physical signal measurement.

### Cross-check outside the app

- **macOS System Information:** Hold Option and open the Apple menu, then choose **System Information** and select **Graphics/Displays**. Check the intended display and its reported resolution; compare refresh rate and other fields where available. The same report can be read in Terminal with the command below. This is useful for checking display identity and timing, but an `RGB` framebuffer or a reported color depth does not establish the HDMI encoding or Full Range. [Apple's System Information guide](https://support.apple.com/guide/system-information/system-information-syspr35536/mac)

  ```bash
  system_profiler SPDisplaysDataType
  ```

  Expect a display report. A missing display or field means this report cannot verify it. The command is read-only and needs no cleanup.

- **The monitor's own menu (OSD):** Open its Information or Input Signal page for the HDMI input in use. If the monitor reports the received signal's encoding and quantization range, compare those values with `RGB` and `Full`. An input setting or picture preset named RGB, Full or sRGB is not itself a measurement of the incoming signal. Menu names and available fields vary; if range is not reported, keep the hardware result unverified.
- **Visual cross-check:** View grayscale gradients and near-black/near-white detail on the target screen, for example with the [EIZO Monitor Test](https://www.eizo.com/library/basics/eizo-monitor-test/). Look for lost dark or bright detail and unexpected tonal changes while keeping the picture settings consistent. A visual test can reveal a problem, but a good-looking image does not prove RGB Full: gamma, HDR and monitor processing also affect it.

### Check an EDID installation separately

1. In **Installation configuration**, check for **Installed. Reconnect the display to load it.** Expand **Configuration details** and copy **File location**. Do not guess the vendor or product IDs.
2. Optionally inspect that file in Finder using **Go > Go to Folder…** (**⇧⌘G**), or validate it in Terminal. Replace the quoted placeholder with the copied path:

   ```bash
   plutil -lint "/paste/the/path/from/File location"
   ```

   `OK` means the installed file is a valid plist, not that macOS loaded its EDID or is transmitting RGB Full. A missing file, permission error or parse error must be resolved before treating the file check as passed. This command only reads the file and needs no cleanup.
3. Reconnect the HDMI cable, reopen the app and click **Refresh**. Repeat the live-mode and OSD checks above. If the file is installed but the live mode remains YCbCr or Limited, the RGB Full target has not been established; installing the override alone is insufficient evidence.
4. To undo an app-managed override, use **Restore…**, then reconnect and refresh again. It restores the original file, or removes the app's file if none existed before. It does not automatically restore a previously selected native connection mode. If external changes block restoration, inspect those changes instead of deleting the file blindly.

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
