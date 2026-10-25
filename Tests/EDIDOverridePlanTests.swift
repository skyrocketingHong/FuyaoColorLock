import Darwin
import Foundation

@main
struct EDIDOverridePlanTests {
    private static let fileManager = FileManager.default

    static func main() throws {
        try installAndRestoreWithoutOriginal()
        try mergesAndRestoresOriginalExactly()
        try rejectsChangeBeforeInstallation()
        try rejectsExternalChangeBeforeRestore()
        try rejectsSymbolicLinks()
        try refusesDuplicateInstallation()
        try rejectsDamagedBackupState()
        try occupiedLockPreventsChanges()
        print("Passed 8 unprivileged override-plan regression groups.")
    }

    private static func installAndRestoreWithoutOriginal() throws {
        try withFixture { fixture in
            let payload = try EDIDOverridePlan.mergedPlist(patch: fixture.patch, existing: nil)
            let result = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: payload,
                                                             expectedCurrent: nil, ownerID: getuid()))
            try expect(result.status == 0, "Install failed: \(result.output)")
            try expect(try Data(contentsOf: fixture.paths.destination) == payload, "Installed payload differs")
            try expect(fileManager.fileExists(atPath: fixture.paths.noOriginal.path), "Absence marker was not saved")
            try expect(!fileManager.fileExists(atPath: fixture.paths.backup.path), "A backup must not be invented")
            try expect(try Data(contentsOf: fixture.paths.receipt) == payload, "Receipt must contain exact installed data")
            let restored = try run(EDIDOverridePlan.restoreScript(paths: fixture.paths,
                                                                expectedCurrent: payload, ownerID: getuid()))
            try expect(restored.status == 0, "Restore failed: \(restored.output)")
            try expect(!fileManager.fileExists(atPath: fixture.paths.destination.path), "New override must be removed")
            try expect(!fileManager.fileExists(atPath: fixture.paths.stateDirectory.path), "Managed backup state must be cleared")
        }
    }

    private static func mergesAndRestoresOriginalExactly() throws {
        try withFixture { fixture in
            let original = try originalPlist()
            try prepareDestination(fixture.paths, data: original)
            let payload = try EDIDOverridePlan.mergedPlist(patch: fixture.patch, existing: original)
            let parsed = try PropertyListSerialization.propertyList(from: payload, format: nil) as! [String: Any]
            try expect(parsed["DisplayProductName"] as? String == "Existing custom name", "Existing override keys must be preserved")
            try expect(parsed["scale-resolutions"] as? [Data] == [Data([1, 2, 3, 4])], "Existing resolution data must be preserved")
            let result = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: payload,
                                                             expectedCurrent: original, ownerID: getuid()))
            try expect(result.status == 0, "Existing-file installation failed: \(result.output)")
            try expect(try Data(contentsOf: fixture.paths.backup) == original, "Original bytes must be backed up exactly")
            try expect(!fileManager.fileExists(atPath: fixture.paths.noOriginal.path), "Existing override must not have an absence marker")
            let restored = try run(EDIDOverridePlan.restoreScript(paths: fixture.paths,
                                                                expectedCurrent: payload, ownerID: getuid()))
            try expect(restored.status == 0, "Existing-file restore failed: \(restored.output)")
            try expect(try Data(contentsOf: fixture.paths.destination) == original, "Original bytes must be restored exactly")
        }
    }

    private static func rejectsChangeBeforeInstallation() throws {
        try withFixture { fixture in
            let original = try originalPlist()
            let external = Data("external-change-before-authorization".utf8)
            try prepareDestination(fixture.paths, data: external)
            let payload = try EDIDOverridePlan.mergedPlist(patch: fixture.patch, existing: original)
            let result = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: payload,
                                                             expectedCurrent: original, ownerID: getuid()))
            try expect(result.status != 0 && result.output.contains("authorization was pending"), "Changed target must reject installation")
            try expect(try Data(contentsOf: fixture.paths.destination) == external, "External file must remain untouched")
            try expect(!fileManager.fileExists(atPath: fixture.paths.stateDirectory.path), "Failed install must not leave managed state")
        }
    }

    private static func rejectsExternalChangeBeforeRestore() throws {
        for hasOriginal in [false, true] {
            try withFixture { fixture in
                let original = hasOriginal ? try originalPlist() : nil
                if let original { try prepareDestination(fixture.paths, data: original) }
                let payload = try EDIDOverridePlan.mergedPlist(patch: fixture.patch, existing: original)
                let installed = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: payload,
                                                                    expectedCurrent: original, ownerID: getuid()))
                try expect(installed.status == 0, "Restore fixture install failed: \(installed.output)")
                let external = Data("external-change-after-installation".utf8)
                try external.write(to: fixture.paths.destination)
                // Even a fresh UI readback must not authorize deleting an unrelated edit.
                let result = try run(EDIDOverridePlan.restoreScript(paths: fixture.paths,
                                                                  expectedCurrent: external, ownerID: getuid()))
                try expect(result.status != 0 && result.output.contains("outside this app"), "External target edit must reject restore")
                try expect(try Data(contentsOf: fixture.paths.destination) == external, "External edit must remain untouched")
                try expect(fileManager.fileExists(atPath: fixture.paths.receipt.path), "Rejected restore must retain its receipt")
                if let original {
                    try expect(try Data(contentsOf: fixture.paths.backup) == original, "Rejected restore must retain its original backup")
                }
            }
        }
    }

    private static func rejectsSymbolicLinks() throws {
        try withFixture { fixture in
            let victim = fixture.root.appendingPathComponent("unrelated-file")
            let bytes = Data("must-remain-untouched".utf8)
            try bytes.write(to: victim)
            try fileManager.createDirectory(at: fixture.paths.vendorDirectory, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: fixture.paths.destination, withDestinationURL: victim)
            let result = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: fixture.patch.plistData,
                                                             expectedCurrent: bytes, ownerID: getuid()))
            try expect(result.status != 0 && result.output.contains("Symbolic links"), "Symbolic-link target must be rejected")
            try expect(try Data(contentsOf: victim) == bytes, "Symlink referent must remain untouched")
        }
        try withFixture { fixture in
            let other = fixture.root.appendingPathComponent("unrelated-directory")
            try fileManager.createDirectory(at: other, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: fixture.paths.library.appendingPathComponent("Displays"), withDestinationURL: other)
            let result = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: fixture.patch.plistData,
                                                             expectedCurrent: nil, ownerID: getuid()))
            try expect(result.status != 0 && result.output.contains("Unsafe override directory"), "Symbolic-link ancestor must be rejected")
            try expect(try fileManager.contentsOfDirectory(atPath: other.path).isEmpty, "Symlink directory must remain untouched")
        }
    }

    private static func refusesDuplicateInstallation() throws {
        try withFixture { fixture in
            let payload = fixture.patch.plistData
            let first = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: payload,
                                                            expectedCurrent: nil, ownerID: getuid()))
            try expect(first.status == 0, "Duplicate-install fixture failed: \(first.output)")
            let second = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: payload,
                                                             expectedCurrent: payload, ownerID: getuid()))
            try expect(second.status != 0 && second.output.contains("existing managed backup"), "Duplicate install must preserve original backup state")
            try expect(try Data(contentsOf: fixture.paths.destination) == payload, "Duplicate install must not change target")
            try expect(fileManager.fileExists(atPath: fixture.paths.noOriginal.path), "Duplicate install must retain absence marker")
            let files = try fileManager.contentsOfDirectory(atPath: fixture.paths.stateRoot.path)
            try expect(files == [fixture.paths.stateDirectory.lastPathComponent], "Duplicate install must not leave staging directories")
        }
    }

    private static func rejectsDamagedBackupState() throws {
        for damage in ["missingReceipt", "ambiguousBackup", "symlinkBackup"] {
            try withFixture { fixture in
                let original = try originalPlist()
                try prepareDestination(fixture.paths, data: original)
                let payload = try EDIDOverridePlan.mergedPlist(patch: fixture.patch, existing: original)
                let installed = try run(EDIDOverridePlan.installScript(paths: fixture.paths, payload: payload,
                                                                    expectedCurrent: original, ownerID: getuid()))
                try expect(installed.status == 0, "Backup-state fixture install failed: \(installed.output)")
                switch damage {
                case "missingReceipt":
                    try fileManager.removeItem(at: fixture.paths.receipt)
                case "ambiguousBackup":
                    try Data().write(to: fixture.paths.noOriginal)
                default:
                    try fileManager.removeItem(at: fixture.paths.backup)
                    try fileManager.createSymbolicLink(at: fixture.paths.backup, withDestinationURL: fixture.paths.receipt)
                }
                let restored = try run(EDIDOverridePlan.restoreScript(paths: fixture.paths,
                                                                    expectedCurrent: payload, ownerID: getuid()))
                try expect(restored.status != 0, "Damaged backup state must reject restore: \(damage)")
                try expect(try Data(contentsOf: fixture.paths.destination) == payload, "Rejected restore must leave target untouched")
            }
        }
    }

    private static func occupiedLockPreventsChanges() throws {
        try withFixture { fixture in
            let paths = fixture.paths
            let payload = fixture.patch.plistData
            let lock = URL(fileURLWithPath: paths.stateDirectory.path + ".lock", isDirectory: true)
            try fileManager.createDirectory(at: paths.stateRoot, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o755])
            try fileManager.createDirectory(at: lock, withIntermediateDirectories: false)
            let blockedInstall = try run(EDIDOverridePlan.installScript(paths: paths, payload: payload,
                                                                       expectedCurrent: nil, ownerID: getuid()))
            try expect(blockedInstall.status != 0 && blockedInstall.output.contains("Another override operation"),
                       "Occupied lock must reject installation")
            try expect(!fileManager.fileExists(atPath: paths.destination.path), "Blocked install must not create an override")
            try expect(fileManager.fileExists(atPath: lock.path), "A caller must not remove another operation's lock")
            try fileManager.removeItem(at: lock)

            let installed = try run(EDIDOverridePlan.installScript(paths: paths, payload: payload,
                                                                 expectedCurrent: nil, ownerID: getuid()))
            try expect(installed.status == 0, "Install should work after releasing the lock: \(installed.output)")
            try expect(!fileManager.fileExists(atPath: lock.path), "Successful install must release its lock")

            try fileManager.createDirectory(at: lock, withIntermediateDirectories: false)
            let blockedRestore = try run(EDIDOverridePlan.restoreScript(paths: paths, expectedCurrent: payload, ownerID: getuid()))
            try expect(blockedRestore.status != 0 && blockedRestore.output.contains("Another override operation"),
                       "Occupied lock must reject restoration")
            try expect(try Data(contentsOf: paths.destination) == payload, "Blocked restore must leave installed bytes intact")
            try expect(try Data(contentsOf: paths.receipt) == payload, "Blocked restore must leave receipt intact")
            try expect(fileManager.fileExists(atPath: lock.path), "Restore must not remove another operation's lock")
            try fileManager.removeItem(at: lock)

            let restored = try run(EDIDOverridePlan.restoreScript(paths: paths, expectedCurrent: payload, ownerID: getuid()))
            try expect(restored.status == 0, "Restore should work after releasing the lock: \(restored.output)")
            try expect(!fileManager.fileExists(atPath: lock.path), "Successful restore must release its lock")
            try expect(!fileManager.fileExists(atPath: paths.destination.path), "Restore should remove a newly installed override")
        }
    }

    private struct Fixture {
        let root: URL
        let patch: EDIDPatch
        let paths: EDIDOverridePaths
    }

    private static func withFixture(_ action: (Fixture) throws -> Void) throws {
        // Each system-like hierarchy is strictly beneath this temporary root.
        let root = fileManager.temporaryDirectory.appendingPathComponent("FuyaoOverrideTests-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("Library with 'quotes' $() `ticks`", isDirectory: true)
        try fileManager.createDirectory(at: library, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: root) }
        let patch = try EDIDPatch.make(from: fixtureEDID())
        let paths = EDIDOverridePaths(patch: patch, library: library)
        guard paths.library.path.hasPrefix(root.path + "/"), paths.library.path != "/Library" else {
            throw Failure(message: "Unsafe test directory")
        }
        try action(Fixture(root: root, patch: patch, paths: paths))
    }

    private static func prepareDestination(_ paths: EDIDOverridePaths, data: Data) throws {
        try fileManager.createDirectory(at: paths.vendorDirectory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o755])
        try data.write(to: paths.destination)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.destination.path)
    }

    private static func originalPlist() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "DisplayProductName": "Existing custom name",
            "scale-resolutions": [Data([1, 2, 3, 4])],
            "IODisplayEDID": Data([5, 6, 7]),
        ], format: .binary, options: 0)
    }

    private static func run(_ script: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    private static func fixtureEDID() -> Data {
        var bytes = [UInt8](repeating: 0, count: 256)
        bytes.replaceSubrange(0..<8, with: [0, 255, 255, 255, 255, 255, 255, 0])
        bytes.replaceSubrange(8..<12, with: [0x10, 0xAC, 0x34, 0x12])
        bytes[18] = 1
        bytes[19] = 4
        bytes[126] = 1
        bytes.replaceSubrange(128..<132, with: [2, 3, 4, 0x30])
        for start in [0, 128] {
            bytes[start + 127] = UInt8((256 - bytes[start..<(start + 127)].reduce(0) { $0 + Int($1) } % 256) % 256)
        }
        return Data(bytes)
    }

    private struct Failure: Error { let message: String }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
}
