import CoreGraphics
import Foundation

struct DisplaySelectionCandidate: Equatable {
    let id: String
    let cgDisplayID: CGDirectDisplayID
}

struct DisplayOpenContext: Equatable {
    let cgDisplayID: CGDirectDisplayID?
    let stableDisplayID: String?
    let name: String?
    let isAmbiguous: Bool

    static let unknown = DisplayOpenContext(cgDisplayID: nil, stableDisplayID: nil, name: nil, isAmbiguous: false)
}

enum DisplaySelectionIssue: Equatable {
    case unknownScreen
    case unavailableDisplay
    case ambiguousScreen
}

/// Selection belongs to one popover presentation. Resolving its source screen
/// never changes display settings, and later refreshes never pick a substitute.
struct DisplaySelectionState {
    private(set) var selectedDisplayID: String?
    private(set) var issue: DisplaySelectionIssue? = .unknownScreen
    private var context = DisplayOpenContext.unknown
    private var retainedDisplayID: String?
    private var isManual = false

    mutating func open(context: DisplayOpenContext, candidates: [DisplaySelectionCandidate]) {
        self.context = context
        retainedDisplayID = nil
        isManual = false
        resolve(candidates: candidates, allowsImmediateCGMatch: true)
    }

    mutating func select(_ id: String?, candidates: [DisplaySelectionCandidate]) {
        isManual = true
        retainedDisplayID = id
        resolve(candidates: candidates, allowsImmediateCGMatch: false)
    }

    mutating func reconcile(candidates: [DisplaySelectionCandidate]) {
        resolve(candidates: candidates, allowsImmediateCGMatch: false)
    }

    private mutating func resolve(candidates: [DisplaySelectionCandidate], allowsImmediateCGMatch: Bool) {
        if isManual || retainedDisplayID != nil {
            guard let retainedDisplayID,
                  candidates.filter({ $0.id == retainedDisplayID }).count == 1 else {
                selectedDisplayID = nil
                issue = .unavailableDisplay
                return
            }
            selectedDisplayID = retainedDisplayID
            issue = nil
            return
        }

        guard !context.isAmbiguous else {
            selectedDisplayID = nil
            issue = .ambiguousScreen
            return
        }
        guard let cgDisplayID = context.cgDisplayID else {
            selectedDisplayID = nil
            issue = .unknownScreen
            return
        }
        // When the first catalog is late, an observed stable identity is
        // required: a recycled CG number must not select a different monitor.
        guard context.stableDisplayID != nil || allowsImmediateCGMatch else {
            selectedDisplayID = nil
            issue = .unavailableDisplay
            return
        }
        let matches = candidates.filter {
            if let stableID = context.stableDisplayID { return $0.id == stableID }
            return $0.cgDisplayID == cgDisplayID
        }
        guard matches.count == 1, let match = matches.first else {
            selectedDisplayID = nil
            issue = matches.count > 1 ? .ambiguousScreen : .unavailableDisplay
            return
        }
        retainedDisplayID = match.id
        selectedDisplayID = match.id
        issue = nil
    }
}

struct ScreenPlacement: Equatable {
    let displayID: CGDirectDisplayID?
    let frame: CGRect
    let visibleFrame: CGRect
    let name: String
    let isMirrored: Bool
}

struct ScreenLocationResult: Equatable {
    let screen: ScreenPlacement?
    let isAmbiguous: Bool
}

enum ScreenLocationPolicy {
    /// Both the pointer and frames use AppKit screen coordinates in points.
    /// Use full frames because the menu bar lies outside visibleFrame.
    static func locate(pointer: CGPoint?, fallbackDisplayID: CGDirectDisplayID?,
                       screens: [ScreenPlacement]) -> ScreenLocationResult {
        if let pointer {
            guard pointer.x.isFinite, pointer.y.isFinite else {
                return ScreenLocationResult(screen: nil, isAmbiguous: false)
            }
            let hits = screens.filter { containsMousePoint(pointer, frame: $0.frame) }
            if hits.count == 1 {
                return ScreenLocationResult(screen: hits[0], isAmbiguous: hits[0].isMirrored)
            }
            if hits.count > 1 {
                return ScreenLocationResult(screen: nil, isAmbiguous: true)
            }
            return ScreenLocationResult(screen: nil, isAmbiguous: false)
        }
        if let fallbackDisplayID {
            let matches = screens.filter { $0.displayID == fallbackDisplayID }
            if matches.count == 1 {
                return ScreenLocationResult(screen: matches[0], isAmbiguous: matches[0].isMirrored)
            }
            if matches.count > 1 { return ScreenLocationResult(screen: nil, isAmbiguous: true) }
        }
        return ScreenLocationResult(screen: nil, isAmbiguous: false)
    }

    private static func containsMousePoint(_ point: CGPoint, frame: CGRect) -> Bool {
        // Match NSMouseInRect(point, frame, false): a non-flipped AppKit
        // screen includes its top edge, where the menu bar can be clicked.
        point.x >= frame.minX && point.x < frame.maxX
            && point.y > frame.minY && point.y <= frame.maxY
    }

    static func shouldCloseExistingPopover(current: DisplayOpenContext?, incoming: DisplayOpenContext) -> Bool {
        guard let current else { return false }
        if let currentID = current.stableDisplayID, let incomingID = incoming.stableDisplayID {
            return currentID == incomingID && current.isAmbiguous == incoming.isAmbiguous
        }
        if let currentID = current.cgDisplayID, let incomingID = incoming.cgDisplayID {
            return currentID == incomingID && current.isAmbiguous == incoming.isAmbiguous
        }
        return current == incoming
    }
}
