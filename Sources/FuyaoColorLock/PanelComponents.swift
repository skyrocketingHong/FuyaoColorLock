import SwiftUI

struct InformationGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }
}

struct PanelSectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PanelActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).controlSize(.small)
        } else {
            content.buttonStyle(.bordered).controlSize(.small)
        }
    }
}

struct PanelScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            content
        }
    }
}

struct PanelErrorAlert: ViewModifier {
    let title: LocalizedStringKey
    @Binding var message: String?

    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) {
            content.alert(title, item: $message) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        } else {
            content.alert(title, isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }
}

extension View {
    @ViewBuilder
    func onPanelChange<Value: Equatable>(of value: Value, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value, action)
        } else {
            onChange(of: value) { _ in action() }
        }
    }
}
