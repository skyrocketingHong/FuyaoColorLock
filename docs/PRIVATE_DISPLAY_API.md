# Native display mode implementation

[简体中文](PRIVATE_DISPLAY_API_ZH.md)

Reviewed on 2026-10-25. This record distinguishes static binary evidence, read-only runtime checks and untested physical writes.

## Evidence

The public [BetterDisplay CLI](https://raw.githubusercontent.com/waydabber/betterdisplaycli/main/betterdisplaycli.swift) sends JSON requests through DistributedNotificationCenter. The [official command reference](https://github.com/waydabber/BetterDisplay/wiki/Integration-features%2C-CLI) exposes `connectionMode`, but the underlying implementation is in the main application. FuyaoColorLock's original `cff69aa` integration invoked that application; removing the dependency did not supply a replacement writer.

Static analysis used the official [BetterDisplay 5.1.1 release](https://github.com/waydabber/BetterDisplay/releases/tag/v5.1.1), published on 2026-10-06. Its DMG SHA-256 is `533ce08c91a02e0fdca2bc0e461404968ab18d32bbd9fd3314218e1a8d51c1de`; the extracted main binary is `682befb88bb5f199cb2568a4aa91ffc683c7e4141216eba72418a52512e0204e`. No application was installed or launched.

| ARM64 call site | Operation |
| --- | --- |
| `0x100a89db8` | `+[CADisplay displays]` |
| `0x100a89ed8` | `displayId`, matched to the CG display ID |
| `0x100a8953c` | `availableModes` |
| `0x100a8b2c0` | `CADisplayMode.internalRepresentation`, a 64-bit mode ID |
| `0x100a8b304` | `setCurrentMode:`, passing a native mode object |

This QuartzCore route disproves the earlier conclusion that no direct mode-setting channel was available. Excluding CGS, SLS and IOConnect paths was insufficient.

## Runtime cross-check

Read-only probes checked method encodings and called getters on three external displays. `setCurrentMode:` has encoding `v24@0:8@16` and returns no success value. Mode IDs, width, height and bit depth return unsigned 64-bit integers; refresh rate returns Double; color fields return objects; VRR and virtual flags return Bool.

The native lists contained 197, 295 and 438 modes. Restricting to the same resolution, exact refresh rate, HDR and VRR states left 6, 5 and 6 compatible modes. The getters and available setter ABI were readable; the setter was never invoked. No display identifier, serial number or raw EDID is included here.

## Independent implementation

`CoreDisplayModes.swift` resolves the system class dynamically, checks the ABI and reads native mode objects. It does not distribute BetterDisplay code or require that application at runtime.

Before a write, the app checks the stable display identity, expected current mode and a fresh available-mode list. Only a unique compatible mode object is passed to the setter. Missing capabilities, reused identifiers and stale selections are rejected. Native mode changes and EDID installation share one mutation gate.

After a request, two complete matching reads 0.5 seconds apart are required for system confirmation, within a six-second window. Later drift or disconnection invalidates the confirmation. This is system readback, not a measurement of the HDMI signal or panel gamut.

Private API behavior can change across macOS versions. Unsupported encodings remain view-only. Physical switching, visual behavior and HDMI RGB Full Range acceptance are pending user testing. The ignored `build/research/` folder retains local analysis output; research binaries and extraction tools are excluded from the app and Git history.
