import SwiftUI

/// Secondary navigation: opening the panel selects its screen automatically.
struct DisplayMenuPicker: View {
    struct Choice: Identifiable, Equatable {
        let id: String
        let name: String
    }

    let choices: [Choice]
    @Binding var selection: String?

    var body: some View {
        Menu {
            ForEach(choices) { choice in
                Button {
                    selection = choice.id
                } label: {
                    if choice.id == selection {
                        Label(title(for: choice), systemImage: "checkmark")
                    } else {
                        Text(title(for: choice))
                    }
                }
            }
        } label: {
            Label("Other displays", systemImage: "display.2")
                .labelStyle(.iconOnly)
                .frame(minWidth: 16, minHeight: 16)
        }
        .menuIndicator(.hidden)
        .modifier(PanelActionStyle())
        .help("View another display.")
        .accessibilityLabel("Other displays")
    }

    private func title(for choice: Choice) -> String {
        let matching = choices.filter { $0.name == choice.name }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.id == choice.id }) else {
            return choice.name
        }
        return "\(choice.name) · \(index + 1)"
    }
}
