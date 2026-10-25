import SwiftUI

enum PanelMetrics {
    static let contentInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 18
    static let rowSpacing: CGFloat = 8
    static let controlMinHeight: CGFloat = 28
    static let actionMinWidth: CGFloat = 60
    static let actionColumnMinWidth: CGFloat = 88
    static let modeRowMinHeight: CGFloat = 40
}

struct InformationGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PanelActionLabel: View {
    let title: LocalizedStringKey
    let minimumWidth: CGFloat

    init(_ title: LocalizedStringKey, minimumWidth: CGFloat = PanelMetrics.actionMinWidth) {
        self.title = title
        self.minimumWidth = minimumWidth
    }

    var body: some View {
        Text(title)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: minimumWidth)
    }
}

struct PanelControlRow<Label: View, Control: View>: View {
    let minimumLabelWidth: CGFloat
    let label: Label
    let control: Control

    init(minimumLabelWidth: CGFloat = 160, @ViewBuilder label: () -> Label,
         @ViewBuilder control: () -> Control) {
        self.minimumLabelWidth = minimumLabelWidth
        self.label = label()
        self.control = control()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                label
                    .frame(minWidth: minimumLabelWidth, maxWidth: .infinity, alignment: .leading)
                control.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                label.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer(minLength: 0)
                    control
                }
            }
        }
        .frame(minHeight: PanelMetrics.controlMinHeight)
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
            content.buttonStyle(.glass).controlSize(.regular)
        } else {
            content.buttonStyle(.bordered).controlSize(.regular)
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
