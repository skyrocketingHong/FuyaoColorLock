import SwiftUI

struct DisplayDetailsView: View {
    let display: PhysicalDisplay
    let preference: DisplayPreference
    let clearTarget: () -> Void

    var body: some View {
        DisclosureGroup("Display details") {
            VStack(alignment: .leading, spacing: 14) {
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
                Text("Connection formats are separate from ICC color profiles. System read-back does not measure the display's physical color output.")
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
                Text("Saved by macOS; may differ from the live connection. The record does not include colorimetry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable:
                Label("No usable record", systemImage: "questionmark.circle")
                Text("macOS has not provided a complete connection record. The active format cannot be determined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .conflicting:
                Label("Conflicting records", systemImage: "exclamationmark.triangle")
                Text("macOS has multiple different records for this display. None is presented as the active format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            Text("The old target cannot be reliably restored from its ID. Saving it did not apply a display mode.")
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
            Label("Driver table · View only", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !hasCurrentTiming, !modes.isEmpty {
                Text("Formats reported across all supported timings. The current timing is unknown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Colorimetry codes are shown as reported by the driver; their color space mapping is unverified.")
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
            .padding(.vertical, 10)
            .accessibilityHint("Read-only driver entry.")
    }
}
