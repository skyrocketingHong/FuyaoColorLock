import CryptoKit
import Foundation

struct EDIDOverridePaths {
    static let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)
    let library: URL
    let vendorDirectory: URL
    let destination: URL
    let stateRoot: URL
    let stateDirectory: URL

    init(patch: EDIDPatch, library: URL = systemLibrary) {
        self.library = library
        let overrides = library.appendingPathComponent("Displays/Contents/Resources/Overrides", isDirectory: true)
        vendorDirectory = overrides.appendingPathComponent(patch.vendorDirectoryName, isDirectory: true)
        destination = vendorDirectory.appendingPathComponent(patch.productFileName)
        stateRoot = overrides.appendingPathComponent(".FuyaoColorLock", isDirectory: true)
        stateDirectory = stateRoot.appendingPathComponent("\(patch.vendorID)-\(patch.productID)", isDirectory: true)
    }

    var receipt: URL { stateDirectory.appendingPathComponent("installed.plist") }
    var backup: URL { stateDirectory.appendingPathComponent("original.plist") }
    var noOriginal: URL { stateDirectory.appendingPathComponent("no-original") }
    var directories: [URL] {
        var result = [library]
        for component in ["Displays", "Contents", "Resources", "Overrides"] {
            result.append(result.last!.appendingPathComponent(component, isDirectory: true))
        }
        return result + [vendorDirectory, stateRoot]
    }
}

enum EDIDOverridePlan {
    static func digest(_ data: Data?) -> String {
        guard let data else { return "missing" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // ASVS 1.2.5: quote at both interpreter boundaries; no display names or
    // user-selected export paths are part of an administrator command.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScript(for script: String) -> String {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    static func mergedPlist(patch: EDIDPatch, existing: Data?) throws -> Data {
        var dictionary: [String: Any]
        if let existing {
            guard existing.count <= 65_536,
                  let parsed = try PropertyListSerialization.propertyList(from: existing, format: nil) as? [String: Any] else {
                throw OverrideError.invalidExistingFile
            }
            dictionary = parsed
        } else {
            dictionary = [:]
        }
        dictionary["DisplayVendorID"] = patch.vendorID
        dictionary["DisplayProductID"] = patch.productID
        dictionary["IODisplayEDID"] = patch.patchedData
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        guard data.count <= 65_536 else { throw OverrideError.invalidExistingFile }
        return data
    }

    static func installScript(paths: EDIDOverridePaths, payload: Data, expectedCurrent: Data?, ownerID: UInt32 = 0) -> String {
        let stage = paths.stateRoot.appendingPathComponent(".pending-\(UUID().uuidString)").path
        let temporary = paths.vendorDirectory.appendingPathComponent(".pending-\(UUID().uuidString)").path
        return preamble(paths: paths, expectedCurrent: expectedCurrent, ownerID: ownerID, createDirectories: true) + """
        [ ! -e "$state" ] && [ ! -L "$state" ] || fail 'An existing managed backup needs attention; installation stopped.'
        stage=\(shellQuote(stage))
        temporary=\(shellQuote(temporary))
        /bin/mkdir -m 755 "$stage"
        cleanup() { /bin/rm -f "$temporary"; if [ -d "$stage" ]; then /bin/rm -f "$stage/installed.plist" "$stage/original.plist" "$stage/no-original"; /bin/rmdir "$stage"; fi; unlock; }
        trap cleanup EXIT
        if [ -f "$target" ]; then /bin/cp -p "$target" "$stage/original.plist"; else /usr/bin/touch "$stage/no-original"; fi
        /usr/bin/printf '%s' \(shellQuote(payload.base64EncodedString())) | /usr/bin/base64 -D > "$stage/installed.plist"
        /usr/bin/plutil -lint "$stage/installed.plist" >/dev/null
        /usr/sbin/chown \(ownerID) "$stage/installed.plist"
        /bin/chmod 644 "$stage/installed.plist"
        /bin/cp -p "$stage/installed.plist" "$temporary"
        /bin/mv "$stage" "$state"
        if ! /bin/mv -f "$temporary" "$target"; then
          /bin/mv "$state" "$stage"
          fail 'Could not install the override; the previous file was preserved.'
        fi
        """
    }

    static func restoreScript(paths: EDIDOverridePaths, expectedCurrent: Data?, ownerID: UInt32 = 0) -> String {
        let temporary = paths.vendorDirectory.appendingPathComponent(".restore-\(UUID().uuidString)").path
        return preamble(paths: paths, expectedCurrent: expectedCurrent, ownerID: ownerID, createDirectories: false) + """
        safe_directory "$state"
        safe_file "$state/installed.plist"
        [ -f "$state/installed.plist" ] || fail 'The managed installation record is missing.'
        safe_file "$state/original.plist"
        safe_file "$state/no-original"
        if [ -f "$state/original.plist" ]; then
          [ ! -e "$state/no-original" ] || fail 'The backup state is ambiguous.'
          if [ "$(digest "$target")" != "$(digest "$state/installed.plist")" ] && [ "$(digest "$target")" != "$(digest "$state/original.plist")" ]; then
            fail 'The override changed outside this app; it was not overwritten.'
          fi
          temporary=\(shellQuote(temporary))
          trap '/bin/rm -f "$temporary"; unlock' EXIT
          /bin/cp -p "$state/original.plist" "$temporary"
          /bin/mv -f "$temporary" "$target"
        elif [ -f "$state/no-original" ]; then
          if [ -e "$target" ]; then
            [ "$(digest "$target")" = "$(digest "$state/installed.plist")" ] || fail 'The override changed outside this app; it was not removed.'
            /bin/rm "$target"
          fi
        else
          fail 'No original-file backup or absence record was found.'
        fi
        /bin/rm "$state/installed.plist"
        /bin/rm -f "$state/original.plist" "$state/no-original"
        /bin/rmdir "$state"
        """
    }

    private static func preamble(paths: EDIDOverridePaths, expectedCurrent: Data?, ownerID: UInt32, createDirectories: Bool) -> String {
        let directoryChecks = paths.directories.map { url in
            let path = shellQuote(url.path)
            return createDirectories
                ? "[ -e \(path) ] || [ -L \(path) ] || /bin/mkdir -m 755 \(path)\nsafe_directory \(path)"
                : "safe_directory \(path)"
        }.joined(separator: "\n")
        // ASVS 5.3.2 and 2.3.3: fixed numeric paths, root-owned non-symlink
        // ancestors, a compare-before-write guard, and a preserved original.
        return """
        set -eu
        umask 022
        fail() { /usr/bin/printf '%s\\n' "$1" >&2; exit 1; }
        safe_directory() {
          [ ! -L "$1" ] && [ -d "$1" ] || fail 'Unsafe override directory.'
          [ "$(/usr/bin/stat -f %u "$1")" = '\(ownerID)' ] || fail 'Unexpected directory owner.'
          permissions=$(/usr/bin/stat -f %Lp "$1")
          [ $((0$permissions & 0022)) -eq 0 ] || fail 'Override directory is writable by other users.'
        }
        safe_file() {
          [ ! -L "$1" ] || fail 'Symbolic links are not accepted for override files.'
          if [ -e "$1" ]; then
            [ -f "$1" ] || fail 'Expected a regular override file.'
            [ "$(/usr/bin/stat -f %u "$1")" = '\(ownerID)' ] || fail 'Unexpected file owner.'
            permissions=$(/usr/bin/stat -f %Lp "$1")
            [ $((0$permissions & 0022)) -eq 0 ] || fail 'Override file is writable by other users.'
          fi
        }
        digest() {
          if [ -f "$1" ]; then result=$(/usr/bin/shasum -a 256 "$1"); /usr/bin/printf '%s' "${result%% *}"; else /usr/bin/printf missing; fi
        }
        \(directoryChecks)
        lock=\(shellQuote(paths.stateDirectory.path + ".lock"))
        /bin/mkdir "$lock" 2>/dev/null || fail 'Another override operation is active, or an interrupted operation left a lock.'
        unlock() { /bin/rmdir "$lock" 2>/dev/null || true; }
        trap unlock EXIT
        target=\(shellQuote(paths.destination.path))
        state=\(shellQuote(paths.stateDirectory.path))
        safe_file "$target"
        [ "$(digest "$target")" = \(shellQuote(digest(expectedCurrent))) ] || fail 'The override changed while authorization was pending; retry after refreshing.'

        """
    }
}

enum OverrideError: LocalizedError {
    case invalidExistingFile
    case unsafeFile
    case unsafeDirectory
    case noPatch
    case authorizationFailed
    case administratorFailure(String)
    case installationChanged

    var errorDescription: String? {
        switch self {
        case .invalidExistingFile: return String(localized: "The existing override is not a supported property list. It has not been changed.")
        case .unsafeFile: return String(localized: "The override path is not a regular file. It has not been changed.")
        case .unsafeDirectory: return String(localized: "The override directory has an unsupported owner, permissions or symbolic link. It has not been changed.")
        case .noPatch: return String(localized: "No supported EDID changes are available for this display.")
        case .authorizationFailed: return String(localized: "The administrator operation was cancelled or failed. Refresh the installation status before trying again.")
        case .administratorFailure(let detail): return String(localized: "The administrator operation failed.") + "\n" + detail
        case .installationChanged: return String(localized: "The override differs from this app's installation record. Restore it manually to preserve external changes.")
        }
    }
}
