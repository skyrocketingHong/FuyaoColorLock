import AppKit
import CoreGraphics

struct ScreenActivation {
    let context: DisplayOpenContext
    let visibleFrame: CGRect?
}

@MainActor
enum ScreenActivationResolver {
    static func capture(event: NSEvent?, fallbackScreen: NSScreen?) -> ScreenActivation {
        let mouseTypes: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        let pointer = event.map { mouseTypes.contains($0.type) } == true ? NSEvent.mouseLocation : nil
        let fallback = event?.window?.screen ?? fallbackScreen
        let result = ScreenLocationPolicy.locate(
            pointer: pointer,
            fallbackDisplayID: fallback.flatMap(displayID),
            screens: currentScreens()
        )
        let id = result.screen?.displayID
        return ScreenActivation(
            context: DisplayOpenContext(cgDisplayID: id,
                stableDisplayID: id.flatMap(DisplayCatalog.stableIdentity),
                name: result.screen?.name, isAmbiguous: result.isAmbiguous),
            visibleFrame: result.screen?.visibleFrame
        )
    }

    static func currentScreens() -> [ScreenPlacement] {
        NSScreen.screens.map { screen in
            let id = displayID(screen)
            return ScreenPlacement(displayID: id, frame: screen.frame, visibleFrame: screen.visibleFrame,
                                   name: screen.localizedName,
                                   isMirrored: id.map { CGDisplayIsInMirrorSet($0) != 0 } ?? false)
        }
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        if #available(macOS 26.0, *) {
            return screen.cgDirectDisplayID
        }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func currentVisibleFrame(for context: DisplayOpenContext?) -> CGRect? {
        guard let context, let id = context.cgDisplayID else { return nil }
        if let stableID = context.stableDisplayID,
           DisplayCatalog.stableIdentity(for: id) != stableID { return nil }
        return NSScreen.screens.first { displayID($0) == id }?.visibleFrame
    }
}
