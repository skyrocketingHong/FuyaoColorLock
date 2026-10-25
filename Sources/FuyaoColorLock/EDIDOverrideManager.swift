import AppKit
import Foundation

struct EDIDOverrideStatus {
    var patch: EDIDPatch?
    var unavailableReason: String?
    var installed = false
    var canRestore = false
    var destinationPath: String?
    var hasConflictingInstall = false
}

@MainActor
final class EDIDOverrideManager: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var lastError: String?
    @Published private(set) var resultDisplayID: String?

    func status(for display: PhysicalDisplay) -> EDIDOverrideStatus {
        guard let edid = display.edid else {
            return EDIDOverrideStatus(unavailableReason: String(localized: "No uniquely matched EDID is available. Reconnect the display and refresh."))
        }
        do {
            let patch = try EDIDPatch.make(from: edid)
            let paths = EDIDOverridePaths(patch: patch)
            try Self.validateExistingDirectories(paths.directories + [paths.stateDirectory])
            let current = try Self.readRegularFile(paths.destination)
            let receipt = try Self.readRegularFile(paths.receipt)
            let backup = try Self.readRegularFile(paths.backup)
            let noOriginal = try Self.readRegularFile(paths.noOriginal)
            let stateExists = FileManager.default.fileExists(atPath: paths.stateDirectory.path)
            let validBackup = (backup != nil) != (noOriginal != nil)
            let matchesReceipt = receipt != nil && current == receipt
            let matchesOriginal = backup != nil ? current == backup : current == nil
            let canRestore = receipt != nil && validBackup && (matchesReceipt || matchesOriginal)
            return EDIDOverrideStatus(
                patch: patch, installed: matchesReceipt, canRestore: canRestore,
                destinationPath: paths.destination.path,
                hasConflictingInstall: stateExists && !canRestore
            )
        } catch {
            return EDIDOverrideStatus(unavailableReason: error.localizedDescription)
        }
    }

    func exportOverride(for display: PhysicalDisplay) {
        guard !isBusy else { return }
        start(for: display)
        do {
            let patch = try makePatch(for: display)
            let panel = NSSavePanel()
            panel.title = String(localized: "Export RGB preference override")
            panel.message = String(localized: "Exporting does not install the override or change the display.")
            panel.nameFieldStringValue = patch.productFileName
            panel.canCreateDirectories = true
            isBusy = true
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { [self] response in
                defer { isBusy = false }
                guard response == .OK, let url = panel.url else { return }
                do {
                    try patch.plistData.write(to: url, options: .atomic)
                    lastMessage = String(localized: "Override exported. Display settings are unchanged.")
                } catch {
                    lastError = error.localizedDescription
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func install(for display: PhysicalDisplay) {
        guard !isBusy, DisplayMutationGate.begin() else { return }
        isBusy = true
        var operationStarted = false
        defer { if !operationStarted { isBusy = false; DisplayMutationGate.end() } }
        start(for: display)
        do {
            let currentStatus = status(for: display)
            guard !currentStatus.hasConflictingInstall, !currentStatus.installed, !currentStatus.canRestore else {
                throw OverrideError.installationChanged
            }
            let patch = try makePatch(for: display)
            let paths = EDIDOverridePaths(patch: patch)
            let current = try Self.readRegularFile(paths.destination)
            let payload = try EDIDOverridePlan.mergedPlist(patch: patch, existing: current)
            guard confirm(
                title: String(localized: "Install RGB preference override?"),
                message: String(localized: "An existing override will be backed up. This applies to displays with the same vendor and product IDs. Administrator approval is required. Reconnect afterwards; RGB Full Range is not guaranteed."),
                action: String(localized: "Install")
            ) else { return }
            operationStarted = true
            perform(script: EDIDOverridePlan.installScript(paths: paths, payload: payload, expectedCurrent: current),
                    for: display,
                    success: String(localized: "Override file installed and read back. Reconnect the display, then verify its output. Full Range remains unverified.")) {
                try Self.readRegularFile(paths.destination) == payload
                    && Self.readRegularFile(paths.receipt) == payload
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore(for display: PhysicalDisplay) {
        guard !isBusy, DisplayMutationGate.begin() else { return }
        isBusy = true
        var operationStarted = false
        defer { if !operationStarted { isBusy = false; DisplayMutationGate.end() } }
        start(for: display)
        do {
            let currentStatus = status(for: display)
            guard currentStatus.canRestore, let patch = currentStatus.patch else {
                throw OverrideError.installationChanged
            }
            let paths = EDIDOverridePaths(patch: patch)
            let current = try Self.readRegularFile(paths.destination)
            let original = try Self.readRegularFile(paths.backup)
            guard confirm(
                title: String(localized: "Restore the original override?"),
                message: String(localized: "The app will restore its backup, or remove its installed file if no override existed before. External changes will not be overwritten. Reconnect the display afterwards."),
                action: String(localized: "Restore")
            ) else { return }
            operationStarted = true
            perform(script: EDIDOverridePlan.restoreScript(paths: paths, expectedCurrent: current),
                    for: display,
                    success: String(localized: "The previous override was restored. Reconnect the display to reload its configuration.")) {
                try Self.readRegularFile(paths.destination) == original
                    && !FileManager.default.fileExists(atPath: paths.stateDirectory.path)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func dismissError() { lastError = nil }

    private func makePatch(for display: PhysicalDisplay) throws -> EDIDPatch {
        guard let edid = display.edid else { throw OverrideError.noPatch }
        let patch = try EDIDPatch.make(from: edid)
        guard patch.hasChanges else { throw OverrideError.noPatch }
        return patch
    }

    private func start(for display: PhysicalDisplay) {
        resultDisplayID = display.id
        lastMessage = nil
        lastError = nil
    }

    private func confirm(title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func perform(script: String, for display: PhysicalDisplay, success: String,
                         verify: @escaping @MainActor () throws -> Bool) {
        isBusy = true
        Task {
            defer { isBusy = false; DisplayMutationGate.end() }
            do {
                try await Self.runAdministratorScript(script)
                guard try verify() else { throw OverrideError.installationChanged }
                lastMessage = success
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private static func readRegularFile(_ url: URL) throws -> Data? {
        let manager = FileManager.default
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: url.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
                    && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 65_536 else {
            throw OverrideError.unsafeFile
        }
        return try Data(contentsOf: url)
    }

    private static func validateExistingDirectories(_ urls: [URL]) throws {
        for url in urls {
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                        && error.code == NSFileReadNoSuchFileError {
                continue
            }
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o022 == 0 else {
                throw OverrideError.unsafeDirectory
            }
        }
    }

    private static func runAdministratorScript(_ script: String) async throws {
        // macOS owns the authentication prompt; the app never handles passwords.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", EDIDOverridePlan.appleScript(for: script)]
            process.standardOutput = FileHandle.nullDevice
            let errors = Pipe()
            process.standardError = errors
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = errors.fileHandleForReading.readDataToEndOfFile()
                    let detail = String(decoding: data.prefix(1200), as: UTF8.self)
                    continuation.resume(throwing: detail.isEmpty || detail.contains("(-128)")
                        ? OverrideError.authorizationFailed : OverrideError.administratorFailure(detail))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
