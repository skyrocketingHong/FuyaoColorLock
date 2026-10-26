import SwiftUI

struct DisplayDetailsView: View {
    let display: PhysicalDisplay
    let preference: DisplayPreference
    let lastRefreshAt: Date?
    let clearTarget: () -> Void

    var body: some View {
        DisclosureGroup("Display details") {
            VStack(alignment: .leading, spacing: 14) {
                if let lastRefreshAt {
                    LabeledContent("Last read") {
                        Text(lastRefreshAt, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                }
                InformationGroup("Saved macOS record") {
                    RecordedModeInformation(state: display.recordedLinkState)
                }
                if let targetID = preference.legacyTargetID {
                    SavedTargetInformation(targetID: targetID, clear: clearTarget)
                }
                if display.liveConnection != nil {
                    SupportedModeInformation(
                        modes: display.currentTiming == nil ? display.allSupportedModes : display.currentModes,
                        hasCurrentTiming: display.currentTiming != nil
                    )
                }
                ReportedTimingInformation(timings: display.timings, currentTimingID: display.currentTimingID)
                Text("System read-back is not a measurement of the panel's color output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
        .font(.callout)
    }
}

private struct RecordedModeInformation: View {
    let state: RecordedLinkState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .recorded(let link):
                Text(link.title)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Historical record; not the live connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable:
                Text("No saved connection record.")
            case .conflicting:
                Label("Saved records disagree.", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

private struct SavedTargetInformation: View {
    let targetID: String
    let clear: () -> Void

    var body: some View {
        InformationGroup("Previously saved target") {
            Text(targetID)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("This old target cannot be restored reliably.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Clear saved target", action: clear)
                .modifier(PanelActionStyle())
                .help("Remove the saved preference without changing the display.")
        }
    }
}

struct SupportedModeInformation: View {
    let modes: [ColorModeEntry]
    let hasCurrentTiming: Bool

    var body: some View {
        InformationGroup("Driver-reported modes") {
            if !hasCurrentTiming, !modes.isEmpty {
                Text("All reported timings; the current timing is unknown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Read-only driver values. Colorimetry mapping is unverified.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if modes.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(modes) { mode in
                        ReadOnlyModeRow(mode: mode)
                        if mode.id != modes.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var emptyMessage: LocalizedStringKey {
        hasCurrentTiming ? "No modes were reported for the current timing."
            : "Modes will appear when the driver reports the current timing."
    }
}

private struct ReportedTimingInformation: View {
    let timings: [DisplayTiming]
    let currentTimingID: Int?

    var body: some View {
        InformationGroup("Reported display timings") {
            Text("Resolution and refresh rate options are read only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(timings) { timing in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(timing.label)
                            .font(.callout.monospacedDigit())
                            .textSelection(.enabled)
                        if timing.id == currentTimingID {
                            Text("Current timing reported by driver").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ReadOnlyModeRow: View {
    let mode: ColorModeEntry

    var body: some View {
        Text(mode.title)
            .font(.callout.monospaced())
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .accessibilityHint("Read-only driver entry.")
    }
}
