import Foundation

@main
struct NativeConnectionModeTests {
    @MainActor
    static func main() throws {
        try opaqueIdentifiersRetainAllBits()
        try compatibleModesPreserveTiming()
        try applyRequiresFreshTargetAndIdentity()
        try readbackNeedsStableCompleteAgreement()
        try mutationsAreSerialized()
        print("Passed 5 native connection mode regressions.")
    }

    private static func opaqueIdentifiersRetainAllBits() throws {
        let first = mode(id: 5_800_644_566_425_800_448)
        let next = mode(id: first.id + 1)
        try expect(first.id != next.id && first != next, "Opaque mode identifiers must not pass through Double")
        try expect(String(first.id) == "5800644566425800448", "Full UInt64 identifier must survive formatting")
    }

    private static func compatibleModesPreserveTiming() throws {
        let current = mode()
        try expect(mode(id: 2, depth: 10).isCompatible(with: current), "Changing only bit depth keeps timing")
        try expect(!mode(width: 2560).isCompatible(with: current), "Resolution changes must remain read-only")
        try expect(!mode(rate: 60.0001).isCompatible(with: current), "Nearby refresh rates must not be treated as equal")
        try expect(!mode(hdr: "HDR10").isCompatible(with: current), "HDR changes must remain read-only")
        try expect(!mode(vrr: true).isCompatible(with: current), "Fixed and variable refresh modes must stay separate")
        try expect(!mode(virtual: true).isCompatible(with: current), "Virtual timings must not be applied to a physical link")
        let snapshot = LiveDisplayConnection(currentMode: current,
            modes: [current, mode(id: 2, depth: 10), mode(id: 3, width: 2560)], isWritable: true)
        try expect(snapshot.compatibleModes.count == 2 && snapshot.otherModes.count == 1,
                   "Capabilities must be partitioned without hiding incompatible modes")
    }

    private static func applyRequiresFreshTargetAndIdentity() throws {
        let current = mode()
        let target = mode(id: 2, depth: 10)
        func decision(_ available: [NativeConnectionMode], canSet: Bool = true,
                      identity: Bool = true, actual: NativeConnectionMode? = current) -> NativeApplyPolicy.Decision {
            NativeApplyPolicy.evaluate(target: target, expectedCurrent: current, current: actual,
                available: available, canSet: canSet, identityMatches: identity)
        }
        try expect(decision([current, target]) == .ready, "A fresh compatible target should be actionable")
        try expect(decision([current]) == .unavailable, "A disappeared target must not reach the setter")
        try expect(decision([current, target], canSet: false) == .unavailable, "Missing setter must remain read-only")
        try expect(decision([current, target], identity: false) == .unavailable, "Reused CG display IDs must not cross displays")
        try expect(decision([current, target], actual: mode(id: 3)) == .unavailable,
                   "Changed current state must invalidate a stale selection")
        try expect(decision([current, target, target]) == .unavailable, "Duplicate native target identities must be rejected")
    }

    private static func readbackNeedsStableCompleteAgreement() throws {
        let target = mode(id: 2, depth: 10)
        var verifier = ModeReadbackVerifier(expected: target)
        try expect(!verifier.observe(nil), "Missing readback cannot confirm a write")
        try expect(!verifier.observe(mode()), "Previous mode cannot confirm a write")
        try expect(!verifier.observe(target), "A single immediate readback is insufficient")
        try expect(!verifier.observe(mode(id: 2, depth: 8)), "Matching ID with differing fields cannot confirm a write")
        try expect(!verifier.observe(target), "A mismatch must reset the consecutive-read count")
        try expect(verifier.observe(target), "Two complete matching readbacks should confirm the system state")
    }

    @MainActor
    private static func mutationsAreSerialized() throws {
        try expect(DisplayMutationGate.begin(), "The first display operation should acquire the gate")
        defer { DisplayMutationGate.end() }
        try expect(!DisplayMutationGate.begin(), "EDID and native mode writes must not overlap")
    }

    private static func mode(id: UInt64 = 1, width: Int = 3840, rate: Double = 60,
                             depth: Int = 8, hdr: String = "SDR", vrr: Bool = false,
                             virtual: Bool = false) -> NativeConnectionMode {
        NativeConnectionMode(id: id, width: width, height: 2160, refreshRateHz: rate,
            bitDepth: depth, colorMode: "RGBFullRange", colorGamut: "gamut_SRGB", hdrMode: hdr,
            isVRR: vrr, isVirtual: virtual)
    }

    private struct Failure: Error { let message: String }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
}
