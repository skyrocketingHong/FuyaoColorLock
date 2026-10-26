import CoreGraphics
import Foundation

@main
struct DisplaySelectionTests {
    static func main() throws {
        try openingFollowsTheActivatingScreen()
        try manualChoiceSurvivesRefreshButNotReopen()
        try disconnectNeverSelectsAnotherDisplay()
        try lateCatalogRequiresStableIdentity()
        try reusedCGIdentifierCannotCrossDisplays()
        try unresolvedOrMirroredContextsHaveNoImplicitTarget()
        try screenGeometryUsesFullAppKitFrames()
        try sameScreenClosesAndAnotherScreenReopens()
        print("Passed 8 display-selection regression groups.")
    }

    private static let a = DisplaySelectionCandidate(id: "uuid-test-a", cgDisplayID: 101)
    private static let b = DisplaySelectionCandidate(id: "uuid-test-b", cgDisplayID: 202)
    private static let both = [a, b]

    private static func context(_ candidate: DisplaySelectionCandidate, name: String = "Same name") -> DisplayOpenContext {
        DisplayOpenContext(cgDisplayID: candidate.cgDisplayID, stableDisplayID: candidate.id,
                           name: name, isAmbiguous: false)
    }

    private static func openingFollowsTheActivatingScreen() throws {
        var state = DisplaySelectionState()
        state.open(context: context(b), candidates: both)
        try expect(state.selectedDisplayID == b.id && state.issue == nil, "Opening on B must not choose the first display A")
        state.open(context: context(a), candidates: both)
        try expect(state.selectedDisplayID == a.id, "A new presentation must follow its new source screen")
    }

    private static func manualChoiceSurvivesRefreshButNotReopen() throws {
        var state = DisplaySelectionState()
        state.open(context: context(a), candidates: both)
        state.select(b.id, candidates: both)
        state.reconcile(candidates: both.reversed())
        try expect(state.selectedDisplayID == b.id, "Polling must not undo a manual selection")
        state.open(context: context(a), candidates: both)
        try expect(state.selectedDisplayID == a.id, "Reopening restores automatic screen context")
    }

    private static func disconnectNeverSelectsAnotherDisplay() throws {
        var state = DisplaySelectionState()
        state.open(context: context(a), candidates: both)
        state.reconcile(candidates: [b])
        try expect(state.selectedDisplayID == nil && state.issue == .unavailableDisplay,
                   "A disappearing target must not silently become B")
        let reconnected = DisplaySelectionCandidate(id: a.id, cgDisplayID: 303)
        state.reconcile(candidates: [b, reconnected])
        try expect(state.selectedDisplayID == a.id, "A stable physical identity survives a new CG identifier")
        state.select(b.id, candidates: both)
        state.reconcile(candidates: [a])
        try expect(state.selectedDisplayID == nil, "A disappearing manual target has no implicit replacement")
    }

    private static func lateCatalogRequiresStableIdentity() throws {
        var state = DisplaySelectionState()
        state.open(context: context(a), candidates: [])
        state.reconcile(candidates: [DisplaySelectionCandidate(id: a.id, cgDisplayID: 303)])
        try expect(state.selectedDisplayID == a.id, "A late catalog can resolve a captured stable identity")
        let weakContext = DisplayOpenContext(cgDisplayID: 101, stableDisplayID: nil, name: nil, isAmbiguous: false)
        state.open(context: weakContext, candidates: [])
        state.reconcile(candidates: both)
        try expect(state.selectedDisplayID == nil, "A late CG-only lookup must not guess after identifier reuse")
        state.open(context: weakContext, candidates: both)
        try expect(state.selectedDisplayID == a.id, "A unique immediate CG mapping remains usable")
        state.open(context: context(a), candidates: [])
        state.select(b.id, candidates: [b])
        state.reconcile(candidates: both)
        try expect(state.selectedDisplayID == b.id, "A late automatic match must not override the user's manual choice")
    }

    private static func reusedCGIdentifierCannotCrossDisplays() throws {
        var state = DisplaySelectionState()
        let replacement = DisplaySelectionCandidate(id: "uuid-test-replacement", cgDisplayID: a.cgDisplayID)
        state.open(context: context(a), candidates: [replacement, b])
        try expect(state.selectedDisplayID == nil, "A reused CG number must not override a captured stable identity")
        state.open(context: context(a), candidates: both)
        state.reconcile(candidates: [replacement, b])
        try expect(state.selectedDisplayID == nil, "An open panel must not retarget to a replacement display")
    }

    private static func unresolvedOrMirroredContextsHaveNoImplicitTarget() throws {
        var state = DisplaySelectionState()
        state.open(context: .unknown, candidates: both)
        try expect(state.selectedDisplayID == nil && state.issue == .unknownScreen, "Unknown screens require an explicit selection")
        state.open(context: DisplayOpenContext(cgDisplayID: 999, stableDisplayID: "uuid-built-in", name: "Built-in", isAmbiguous: false), candidates: both)
        try expect(state.selectedDisplayID == nil && state.issue == .unavailableDisplay, "Built-in or uncatalogued screens must not masquerade as an external display")
        state.open(context: DisplayOpenContext(cgDisplayID: a.cgDisplayID, stableDisplayID: a.id, name: "Mirror", isAmbiguous: true), candidates: both)
        try expect(state.selectedDisplayID == nil && state.issue == .ambiguousScreen, "Mirrored physical displays cannot be resolved from shared pointer coordinates")
        state.select(a.id, candidates: both)
        try expect(state.selectedDisplayID == a.id && state.issue == nil, "An explicit choice is still available in ambiguous context")
    }

    private static func screenGeometryUsesFullAppKitFrames() throws {
        let primary = screen(id: 101, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let left = screen(id: 202, frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080))
        let screens = [primary, left]
        let menuBarPoint = CGPoint(x: -1000, y: 879)
        let result = ScreenLocationPolicy.locate(pointer: menuBarPoint, fallbackDisplayID: 101, screens: screens)
        try expect(result.screen?.displayID == 202, "A menu-bar point on a negative-origin screen must beat the primary-window fallback")
        try expect(!left.visibleFrame.contains(menuBarPoint), "The fixture exercises the excluded menu bar, not visibleFrame")
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: -1000, y: 880), fallbackDisplayID: 101, screens: screens).screen?.displayID == 202,
                   "AppKit's inclusive top edge must not fall back to the primary screen")
        let upper = screen(id: 303, frame: CGRect(x: 0, y: 900, width: 1440, height: 900))
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: 100, y: 900), fallbackDisplayID: nil, screens: [primary, upper]).screen?.displayID == 101,
                   "A shared vertical boundary belongs to the lower screen's top edge")
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: 0, y: 500), fallbackDisplayID: nil, screens: screens).screen?.displayID == 101,
                   "A shared horizontal boundary belongs to the right screen's left edge")
        try expect(ScreenLocationPolicy.locate(pointer: nil, fallbackDisplayID: 202, screens: screens).screen?.displayID == 202,
                   "Non-mouse activation uses an explicit window anchor")
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: 99999, y: 0), fallbackDisplayID: nil, screens: screens).screen == nil,
                   "Off-screen points do not select the first screen")
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: 99999, y: 0), fallbackDisplayID: 101, screens: screens).screen == nil,
                   "An unmatched mouse activation must not silently use an unrelated window screen")
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: CGFloat.nan, y: 0), fallbackDisplayID: 101, screens: screens).screen == nil,
                   "An invalid pointer must remain unresolved rather than using a window fallback")
        let overlapping = ScreenPlacement(displayID: 303, frame: primary.frame, visibleFrame: primary.visibleFrame, name: "Mirror", isMirrored: true)
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: 50, y: 50), fallbackDisplayID: 101, screens: [primary, overlapping]).isAmbiguous,
                   "Overlapping screens must not be guessed by array order")
        try expect(ScreenLocationPolicy.locate(pointer: CGPoint(x: 50, y: 50), fallbackDisplayID: nil, screens: [overlapping]).isAmbiguous,
                   "A logical screen in a mirror set remains physically ambiguous")
    }

    private static func sameScreenClosesAndAnotherScreenReopens() throws {
        try expect(ScreenLocationPolicy.shouldCloseExistingPopover(current: context(a), incoming: context(a, name: "Renamed")),
                   "A renamed screen is still the same activation origin")
        try expect(!ScreenLocationPolicy.shouldCloseExistingPopover(current: context(a), incoming: context(b)),
                   "Clicking B while A is open must request reopening, not only closing")
        let moved = DisplaySelectionCandidate(id: a.id, cgDisplayID: 404)
        try expect(ScreenLocationPolicy.shouldCloseExistingPopover(current: context(a), incoming: context(moved)),
                   "Stable physical identity outlives the transient CG number")
    }

    private static func screen(id: CGDirectDisplayID, frame: CGRect) -> ScreenPlacement {
        ScreenPlacement(displayID: id, frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - 24),
            name: "Screen", isMirrored: false)
    }

    private struct Failure: Error { let message: String }
    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
}
