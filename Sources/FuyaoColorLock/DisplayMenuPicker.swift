import AppKit
import SwiftUI

/// A native pop-up button that accepts the panel's width instead of expanding
/// the popover to fit the longest display name.
struct DisplayMenuPicker: NSViewRepresentable {
    struct Choice: Equatable {
        let id: String
        let name: String
    }

    let choices: [Choice]
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.setAccessibilityLabel(String(localized: "Display"))
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if context.coordinator.choices != choices {
            context.coordinator.choices = choices
            button.menu = Self.makeMenu(choices: choices)
        }
        if button.selectedItem?.representedObject as? String != selection,
           let index = button.itemArray.firstIndex(where: { $0.representedObject as? String == selection }) {
            button.selectItem(at: index)
        }
        button.toolTip = choices.first { $0.id == selection }?.name
    }

    static func makeMenu(choices: [Choice]) -> NSMenu {
        let counts = Dictionary(grouping: choices, by: \.name).mapValues(\.count)
        var ordinals: [String: Int] = [:]
        let menu = NSMenu()
        menu.autoenablesItems = false
        for choice in choices {
            ordinals[choice.name, default: 0] += 1
            let title: String
            if counts[choice.name, default: 0] > 1 {
                title = "\(choice.name) (\(ordinals[choice.name, default: 1].formatted()))"
            } else {
                title = choice.name
            }
            // NSPopUpButton's addItem(withTitle:) removes duplicate titles.
            // Add actual menu items so identity always follows the display ID.
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = choice.id
            item.toolTip = choice.name
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    final class Coordinator: NSObject {
        var selection: Binding<String>
        var choices: [Choice] = []

        init(selection: Binding<String>) { self.selection = selection }

        @MainActor @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String else { return }
            selection.wrappedValue = id
        }
    }
}
