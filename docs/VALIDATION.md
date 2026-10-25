# Validation and acceptance

[简体中文](VALIDATION_ZH.md)

Build target: Apple Silicon, macOS 13.0+, version 1.0 (3), built with macOS SDK 27.2 and Swift 6.4.2.

## Completed checks

- 8 display-model regression groups: missing timing, incomplete and conflicting records, mode identity, legacy preferences and unique EDID matching.
- 5 native connection-mode groups: full-width IDs, exact timing compatibility, fresh identity and target checks, repeated readback and mutation exclusion.
- 14 fake-backend mode-lock groups: default opt-out and persistence, drift and readback, fresh IDs after reconnection, incompatible or ambiguous modes, disabling during readback, manual target changes, failure and rate limits, sleep, reused display IDs, shared-gate contention and multiple displays. These tests use isolated preferences and never call the native setter.
- 12 panel geometry checks: different screen origins, narrow or short visible areas, invalid dimensions and shrink-only changes while visible.
- 5 native Swift EDID regression groups, with byte-for-byte parity against Python on 3 synthetic fixtures.
- 8 Python EDID tests, including extension preservation, offsets, checksums and override plist structure.
- 8 unprivileged installation-plan groups: installation and restoration with or without an original file; external changes; symlinks; unusual path characters; damaged backup state; exclusive locks.
- Installation scripts ran only under a temporary test directory. Generated administrator AppleScript compiled without executing it.
- Read-only catalog probing found 3 external displays and uniquely matched EDIDs. Two exposed an active driver timing; the remaining display exposed supported timings without an active timing ID.
- Read-only native probing found live modes and compatible setting candidates for all 3 displays. Setter signatures were checked without calling them.
- The final optimized arm64 app compiled and passed ad hoc signature verification. English and Simplified Chinese resources are included. The Mach-O SDK version is explicitly linked as 27.2, separately from the minimum macOS 13.0 deployment version.

## Implementation review

- Static analysis of BetterDisplay 5.1.1 and a separate read-only runtime probe confirmed the CADisplay implementation route. See [the evidence](PRIVATE_DISPLAY_API.md).
- The UI follows the EC25 native panel reference: fixed canvas, internal scrolling, system groups and controls, selectable technical values. No screenshot or appearance acceptance is claimed.
- Supported actions have wired handlers; unsupported modes have no application action. Loading, unavailable, conflicting and unconfirmed states are explicit.
- Panel order is color mode switching and lock, installation configuration, then application settings and About. Newer systems use native glass controls and scroll-edge effects; macOS 27 uses item-based alerts. About opens the standard system panel. Older supported systems retain fallback controls.

## Manual acceptance

1. Open the built app and switch displays with different mode counts. The panel frame should stay fixed, with content scrolling inside it.
2. Reopen from menu bars on screens with different scaling and positions. Check small-screen clamping, long names, both languages, appearance and keyboard navigation.
3. Confirm unsupported modes remain readable and cannot be applied. Apply a compatible native mode, check the pending state and compare the resulting live format with the request. Confirmation requires two matching reads; timeout must not report success. Saved WindowServer records must not appear as live measurements.
4. Enable **Lock color mode** only after choosing the intended current mode. After wake or reconnection, compare the saved target, lock status and live mode. Disable the switch to stop future restorations. Confirm that incompatible timing changes remain waiting and that a failed manual mode change does not immediately restore the old target.
5. Export an EDID override first. Check the displayed change summary and file path. Installation or restoration requires explicit confirmation and macOS administrator authorization. Turn the mode lock off when checking the effect of the EDID override alone.
6. After installation or restoration, reconnect the display and inspect actual output. File installation is not evidence of RGB Full Range output. Check the application settings and standard About panel at the end of the popover.

The previous running app was gracefully restarted into version 1.0 (3), and launch completion was confirmed with mode locks disabled. No BetterDisplay application, administrator installer or live mode-setting operation was invoked by these checks. No display EEPROM was written. Visual, keyboard, real lock restoration, administrator and HDMI signal acceptance remain pending.

## Reproduce checks

```bash
scripts/test.sh
scripts/build-app.sh
```

Tests write disposable artifacts under `build/` or an automatically cleaned temporary directory. A test failure exits nonzero; inspect the first assertion or compiler diagnostic. The build replaces `build/FuyaoColorLock.app` only after compilation and signature checks succeed. These commands do not install an override or change a display mode.
