# Validation and acceptance

[简体中文](VALIDATION_ZH.md)

Build target: Apple Silicon, macOS 13.0+, version 1.0 (7), built with macOS SDK 27.2 and Swift 6.4.2.

## Completed checks

Build 7 refreshes native mode caches and repairs background lock recovery. The native-mode, lock and display-model suites were run for this change. Unchanged selection, layout and EDID evidence below is retained from its last relevant verification.

- 8 display-selection groups cover selecting on every opening, manual choice retention, disconnection without a substitute, delayed catalog updates, reused CG IDs, ambiguous and unsupported screens, negative origins, menu-bar top edges, vertically adjoining displays and switching an open panel to another screen.
- A read-only AppKit/catalog probe found 3 screens with unique system IDs and 3 exact catalog matches. No names, IDs or coordinates were printed. This does not replace testing actual clicks on replicated menu bars.
- UI source review checked shortened copy, single ownership of current-mode and operation feedback, secondary display navigation, long-text wrapping and preserved disabled states. Same-name menu choices remain keyed by stable identity.
- 8 display-model regression groups: missing timing, incomplete and conflicting records, mode identity, legacy preferences and unique EDID matching.
- 7 native connection-mode groups: full-width IDs, exact timing compatibility, fresh identity and target checks, repeated readback and mutation exclusion; Objective-C mocks additionally cover stale current-mode/available-mode caches, refreshing the same object repeatedly, and rejecting missing or incompatible refresh methods before reading cached getters.
- 33 fake-backend mode-lock groups cover persistence, compatibility, identity, backoff, shared-gate contention and per-display sleep/session recovery. New cases exercise actual background scheduling without manual reconciliation, long lock-screen waits, repeated refreshes, startup with offline locks, catalog recovery, automatic versus manual pauses after reconnection, read failures that must not renew budgets, temporary disconnection during a submitted write, and another display reconnecting during that write. These tests use isolated preferences and never call the native setter.
- The old bridge failed the stale-cache mock. The old scheduler failed the no-notification timing test, and the old lifecycle failed to rearm an automatic pause after a confirmed reconnect. All three regressions pass after the changes. These are controlled code reproductions, not a physical sleep/wake test.
- A missing-wake regression failed against the old lifecycle: repeated reads of an awake, writable display still produced no restoration because the sleep flag remained set. The new lifecycle passes that case by reconciling observed power/session state. This reproduces a code defect, not the user's physical lock-screen sequence.
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
- The display name appears once in the header. The current mode is omitted from the alternative list; stable lock states omit explanatory paragraphs. Export, change counts and file location share configuration details; the read timestamp is in display details, and Quit remains available in application settings with its keyboard shortcut.
- Screen selection uses public AppKit IDs and the captured mouse screen. Right-click Open retains its source on the menu item; keyboard/window fallback does not override a known mouse location. Mirroring or an unavailable source does not silently select another target.
- Wake recovery has a separate bounded read-only check loop and per-display readiness gates. Main-queue sleep, wake and session callbacks enter the main actor synchronously. Unknown session readings do not create a new recovery cycle; automatic pauses and unconfirmed manual-change pauses remain distinct.
- Enabled locks additionally check lightweight topology and connection data every second. Full catalogs retain the 20-second cadence unless data changes. CoreGraphics callbacks enqueue discovery outside the callback; continuous refreshes preserve the earliest scheduled restoration. A confirmed reconnect can renew an automatic budget, while a failed read or the target's own in-flight write cannot.
- Every native snapshot, write preflight and confirmation read refreshes the CADisplay cache through the checked `update` method. Fixed anonymous state and pause-reason transitions are retained at notice level; no display identity or mode parameters are logged.

## Manual acceptance

1. Open the menu-bar icon on each display and check the header and parameters. With A's panel open, click B's icon and check that B is shown in the same action. Right-click Open must follow the original right-click screen. The outer frame remains fixed, with internal scrolling.
2. Choose another display manually, wait for a refresh and verify the choice stays. Close and reopen on a different screen to check automatic selection resumes. Check disconnection, mirroring, long or duplicate names, small-screen clamping, both languages, appearance and keyboard navigation; no unrelated display should become an implicit target.
3. Confirm unsupported modes remain readable and cannot be applied. Apply a compatible native mode, check the pending state and compare the resulting live format with the request. Confirmation requires two matching reads; timeout must not report success. Saved WindowServer records must not appear as live measurements.
4. Enable **Lock color mode** only after choosing the intended current mode. Lock the Mac, wait for the display to power down, then wake and unlock it. Allow the readiness state to finish and compare the saved target, lock status and live mode. Also leave the screen awake at the lock screen for over a minute before unlocking, reconnect a display after an automatic pause, and check a multi-display case where one screen remains asleep. Disable the switch to stop future restorations. Incompatible timing changes must remain waiting, and a failed manual mode change must not immediately restore the old target.
5. Export an EDID override first. Check the displayed change summary and file path. Installation or restoration requires explicit confirmation and macOS administrator authorization. Turn the mode lock off when checking the effect of the EDID override alone.
6. After installation or restoration, reconnect the display and inspect actual output. File installation is not evidence of RGB Full Range output. Check the application settings and standard About panel at the end of the popover.

On 2026-10-29, a read-only probe found one enabled lock with a unique, writable and timing-compatible target, while its current system mode still differed. The previous build 6 process was gracefully restarted into build 7 without changing saved targets. The new app automatically restored that existing target: anonymous logs moved from `retryScheduled` at 19:36:48.531 to `restoring`, then `confirmed` and `matching` at 19:36:50.729 (UTC+8), about 2.2 seconds after the first recorded state. An independent refreshed read then reported one matching lock, zero pending restorations, and three awake displays with readable native modes. This is an observed startup recovery, not a general latency guarantee.

No menu-bar click, screenshot, administrator installation, screen-lock/sleep operation or manual display-mode request was performed. The real setter was exercised only by the restarted app restoring the user's existing enabled lock. System-level restoration and readback were observed; physical sleep/wake recovery, visual behavior, multi-screen interaction, administrator workflow and HDMI signal acceptance remain pending.

## Reproduce checks

```bash
scripts/test.sh
scripts/build-app.sh
```

Tests write disposable artifacts under `build/` or an automatically cleaned temporary directory. A test failure exits nonzero; inspect the first assertion or compiler diagnostic. The build replaces `build/FuyaoColorLock.app` only after compilation and signature checks succeed. These commands do not install an override or change a display mode.
