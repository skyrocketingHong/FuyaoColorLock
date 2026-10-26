import CoreGraphics
import SwiftUI

@MainActor
final class PanelPresentation: ObservableObject {
    @Published private(set) var selectedDisplayID: String?
    @Published private(set) var contextDisplayName: String?
    @Published private(set) var selectionIssue: DisplaySelectionIssue? = .unknownScreen
    @Published var size = PanelLayout.preferredSize

    private var selection = DisplaySelectionState()

    func beginPresentation(context: DisplayOpenContext, displays: [PhysicalDisplay]) {
        contextDisplayName = context.name
        selection.open(context: context, candidates: candidates(displays))
        publishSelection()
    }

    func selectDisplay(_ id: String?, displays: [PhysicalDisplay]) {
        selection.select(id, candidates: candidates(displays))
        publishSelection()
    }

    func reconcile(displays: [PhysicalDisplay]) {
        selection.reconcile(candidates: candidates(displays))
        publishSelection()
    }

    private func candidates(_ displays: [PhysicalDisplay]) -> [DisplaySelectionCandidate] {
        displays.map { DisplaySelectionCandidate(id: $0.id, cgDisplayID: $0.cgDirectDisplayID) }
    }

    private func publishSelection() {
        if selectedDisplayID != selection.selectedDisplayID { selectedDisplayID = selection.selectedDisplayID }
        if selectionIssue != selection.issue { selectionIssue = selection.issue }
    }
}
