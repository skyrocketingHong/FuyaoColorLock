import Foundation

/// A connection color mode preset that maps between the BetterDisplay CLI
/// request syntax and the description fragment the CLI reports back.
struct ConnectionModePreset: Identifiable, Hashable {
    /// BetterDisplay CLI `-connectionMode` value.
    let cliSpec: String
    /// Short menu title.
    let title: String
    /// Fragment that must appear in `get -connectionMode` output when this mode is active.
    let expectedFragment: String

    var id: String { cliSpec }
}

extension ConnectionModePreset {
    /// Modes commonly offered by SDR external displays over DP/HDMI on Apple Silicon.
    /// The CLI accepts extra matching dimensions (refresh rate etc.) but the lock
    /// only pins the pixel format, so plain specs are used.
    static let presets: [ConnectionModePreset] = [
        ConnectionModePreset(cliSpec: "bpc:8+range:full+encoding:rgb",
                             title: "8-bit SDR RGB Full Range",
                             expectedFragment: "8bit SDR RGB Full"),
        ConnectionModePreset(cliSpec: "bpc:8+range:limited+encoding:rgb",
                             title: "8-bit SDR RGB Limited Range",
                             expectedFragment: "8bit SDR RGB Limited"),
        ConnectionModePreset(cliSpec: "bpc:10+range:full+encoding:rgb",
                             title: "10-bit SDR RGB Full Range",
                             expectedFragment: "10bit SDR RGB Full"),
        ConnectionModePreset(cliSpec: "bpc:8+range:limited+encoding:ycbcr444",
                             title: "8-bit SDR YCbCr 4:4:4 Limited Range",
                             expectedFragment: "8bit SDR YCbCr 4:4:4 Limited"),
        ConnectionModePreset(cliSpec: "bpc:10+range:limited+encoding:ycbcr420",
                             title: "10-bit SDR YCbCr 4:2:0 Limited Range",
                             expectedFragment: "10bit SDR YCbCr 4:2:0 Limited"),
        ConnectionModePreset(cliSpec: "bpc:8+range:limited+encoding:ycbcr420",
                             title: "8-bit SDR YCbCr 4:2:0 Limited Range",
                             expectedFragment: "8bit SDR YCbCr 4:2:0 Limited"),
    ]
}
