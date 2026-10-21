import Foundation

/// Thin wrapper around the BetterDisplay CLI that ships with the free version
/// of the app. Only three operations are needed: list physical displays, read
/// the current connection color mode, and set it.
enum BetterDisplayCLI {
    static var executablePath: String {
        UserDefaults.standard.string(forKey: Settings.Keys.cliPath)
            ?? "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
    }

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    enum CLIError: LocalizedError {
        case notInstalled
        case failed(status: Int32, stderr: String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return String(localized: "BetterDisplay CLI not found", comment: "CLI missing")
            case .failed(let status, let stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty
                    ? String(format: String(localized: "BetterDisplay CLI exited with %d", comment: "CLI exit code"), status)
                    : detail
            case .timeout:
                return String(localized: "BetterDisplay CLI timed out", comment: "CLI timeout")
            }
        }
    }

    /// Runs the CLI and returns (stdout, stderr). The CLI talks to the running
    /// BetterDisplay app over a local connection, so a moderate timeout guards
    /// against a hung app.
    private static func run(_ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        guard isAvailable else { throw CLIError.notInstalled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let queue = DispatchQueue(label: "fuyaocolorlock.cli")
        let semaphore = DispatchSemaphore(value: 0)
        queue.async {
            do {
                try process.run()
            } catch {
                semaphore.signal()
                return
            }
            process.waitUntilExit()
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning { process.terminate() }
            throw CLIError.timeout
        }
        guard process.isRunning == false else { throw CLIError.timeout }
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw CLIError.failed(status: process.terminationStatus, stderr: output)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Physical display names as reported by `get -identifiers`. The CLI prints
    /// comma-separated pretty JSON objects (one per device, groups included),
    /// so split on the `},{` boundary and decode each entry.
    static func listDisplayNames() throws -> [String] {
        let output = try run(["get", "-identifiers"])
        var names: [String] = []
        let separator = "\u{0001}"
        let objects = output.replacingOccurrences(of: "},{", with: "}\(separator){")
            .split(separator: Character(separator), omittingEmptySubsequences: true)
        for chunk in objects {
            let text = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.hasPrefix("{"), text.hasSuffix("}"),
                  let data = text.data(using: .utf8),
                  let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  entry["deviceType"] as? String == "Display",
                  let name = entry["name"] as? String, !name.isEmpty else { continue }
            names.append(name)
        }
        return names
    }

    /// Raw `get -connectionMode` line, e.g.
    /// `5800644566425800448 - 3840x2160 60.00Hz Fixed 8bit SDR RGB Full SRGB`.
    static func getConnectionModeLine(displayName: String) throws -> String {
        try run(["get", "-name=\(displayName)", "-connectionMode"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the active connection mode description (the part after "Fixed ").
    static func getConnectionModeDescription(displayName: String) throws -> String {
        let line = try getConnectionModeLine(displayName: displayName)
        guard let fixedRange = line.range(of: "Hz ") else { return line }
        return String(line[fixedRange.upperBound...])
    }

    static func setConnectionMode(_ preset: ConnectionModePreset, displayName: String) throws {
        _ = try run(["set", "-name=\(displayName)", "-connectionMode=\(preset.cliSpec)"],
                    timeout: 20)
    }
}
