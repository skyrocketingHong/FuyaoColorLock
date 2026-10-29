# Native display mode implementation

[简体中文](PRIVATE_DISPLAY_API_ZH.md)

Reviewed on 2026-10-29. This record distinguishes static binary evidence, read-only runtime checks and untested physical writes.

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

## Cached mode refresh

Further static inspection on 2026-10-29 found that BetterDisplay explicitly calls `-[CADisplay update]` before reading modes or preparing a write. These are fixed call sites in the same 5.1.1 ARM64 binary:

| `update` call site | Subsequent operation on the same display object |
| --- | --- |
| `0x100a89530` | `availableModes` at `0x100a8953c`, then `currentMode` at `0x100a897b8` |
| `0x100da53ec` | `currentMode` at `0x100da5410` |
| `0x100a889bc` | Mode-setting helper at `0x100a889cc` |

The selector stub at `0x100ed3020` resolves to `update`; its local runtime encoding is `v16@0:8`. BetterDisplay also registers a CoreGraphics reconfiguration callback, so it does not rely on notifications alone to keep getter results fresh.

Inspection of the loaded system implementation, using a separate probe and copied code bytes, showed that `currentMode` reads a process-local cache. It calls `CA::Display::Display::update()` only when an internal dirty flag is set. The refresh implementation reads display-server data, unpacks mode information, replaces the cached ModeSet and current mode, and sends KVO notifications. No direct mode-setting call was found in that function; indirect provider and MIG paths were not exhaustively audited. Internal field offsets and flags are implementation details, not an ABI contract used by the app.

The bridge now validates and calls `update` before every native snapshot, confirmation readback and write preflight. A missing method or unsupported signature rejects the native snapshot instead of presenting cached values as fresh. Cache refresh does not request a display mode change. Objective-C mock regressions reproduce a stale current mode and mode list, confirm refresh on repeated reads, and reject missing or invalid refresh methods before getters run. They never call a real display setter.

This establishes the cached-getter behavior and the omitted refresh step. The running GUI process's private cache was not inspected directly, so this evidence does not prove that caching was the sole cause of a particular failed recovery. Physical application and wake-cycle acceptance remain separate from cache-refresh validation.

## Independent implementation

`CoreDisplayModes.swift` resolves the system class dynamically, checks the ABI and reads native mode objects. It does not distribute BetterDisplay code or require that application at runtime.

Before a write, the app checks the stable display identity, expected current mode and a fresh available-mode list. Only a unique compatible mode object is passed to the setter. Missing capabilities, reused identifiers and stale selections are rejected. Native mode changes and EDID installation share one mutation gate.

After a request, two complete matching reads 0.5 seconds apart are required for system confirmation, within a six-second window. Later drift or disconnection invalidates the confirmation. This is system readback, not a measurement of the HDMI signal or panel gamut.

Private API behavior can change across macOS versions. Unsupported encodings remain view-only. Physical switching, visual behavior and HDMI RGB Full Range acceptance are pending user testing. The ignored `build/research/` folder retains local analysis output; research binaries and extraction tools are excluded from the app and Git history.
