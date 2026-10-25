import CoreGraphics
import Foundation

@main
enum PanelLayoutTests {
    static func main() {
        var checks = 0
        func expect(_ actual: CGSize, _ expected: CGSize, _ message: String) {
            precondition(actual == expected, "\(message): \(actual) != \(expected)")
            checks += 1
        }

        let regular = CGRect(x: 0, y: 25, width: 1440, height: 875)
        expect(PanelLayout.size(visibleFrame: nil), CGSize(width: 480, height: 660), "No screen fallback")
        expect(PanelLayout.size(visibleFrame: regular), PanelLayout.preferredSize, "Regular display")
        expect(PanelLayout.size(visibleFrame: regular.offsetBy(dx: -2560, dy: -1080)),
               PanelLayout.preferredSize, "Negative screen origins do not change logical size")
        expect(PanelLayout.size(visibleFrame: CGRect(x: 0, y: 0, width: 390, height: 844)),
               CGSize(width: 366, height: 660), "Narrow display clamps width")
        expect(PanelLayout.size(visibleFrame: CGRect(x: 0, y: 0, width: 1024, height: 600)),
               CGSize(width: 480, height: 576), "Short display clamps height")
        expect(PanelLayout.size(visibleFrame: CGRect(x: 0, y: 0, width: 320, height: 240)),
               CGSize(width: 296, height: 216), "Small display clamps both dimensions")
        expect(PanelLayout.size(visibleFrame: CGRect(x: 0, y: 0, width: 10, height: 20)),
               CGSize(width: 1, height: 1), "Tiny valid areas never create negative dimensions")
        expect(PanelLayout.size(visibleFrame: .zero), PanelLayout.preferredSize, "Invalid zero area")
        expect(PanelLayout.size(visibleFrame: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 500)),
               CGSize(width: 480, height: 476), "Invalid width preserves valid height")
        expect(PanelLayout.size(visibleFrame: CGRect(x: 0, y: 0, width: 400, height: CGFloat.nan)),
               CGSize(width: 376, height: 660), "Invalid height preserves valid width")
        let shown = CGSize(width: 400, height: 500)
        expect(PanelLayout.shrinking(shown, toFit: regular), shown, "Visible popover does not grow")
        expect(PanelLayout.shrinking(shown, toFit: CGRect(x: 100, y: 100, width: 360, height: 450)),
               CGSize(width: 336, height: 426), "Visible popover shrinks to newly available area")
        print("PASS: \(checks) panel geometry checks")
    }
}
