import CoreGraphics

/// Content never determines the popover's outer dimensions. All dimensions
/// are logical points; the screen's backing scale is intentionally irrelevant.
enum PanelLayout {
    static let preferredSize = CGSize(width: 480, height: 660)
    static let screenMargin: CGFloat = 24

    static func size(visibleFrame: CGRect?) -> CGSize {
        guard let visibleFrame else { return preferredSize }
        return CGSize(
            width: clamped(preferredSize.width, available: visibleFrame.width),
            height: clamped(preferredSize.height, available: visibleFrame.height)
        )
    }

    static func shrinking(_ current: CGSize, toFit visibleFrame: CGRect?) -> CGSize {
        let available = size(visibleFrame: visibleFrame)
        return CGSize(width: min(current.width, available.width), height: min(current.height, available.height))
    }

    private static func clamped(_ preferred: CGFloat, available: CGFloat) -> CGFloat {
        guard available.isFinite, available > 0 else { return preferred }
        return min(preferred, max(1, available - screenMargin))
    }
}
