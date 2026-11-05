import AppKit

extension NSScreen {
    /// Size of the camera notch, or nil on screens without one.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: right.minX - left.maxX, height: safeAreaInsets.top)
    }

    /// The notch the app draws on a screen without one: as wide as a MacBook notch, as tall as this menu bar.
    var virtualNotchSize: CGSize {
        let menuBar = frame.maxY - visibleFrame.maxY
        // With the menu bar hidden (or not measured yet), fall back to the usual height.
        return CGSize(width: 185, height: menuBar >= 20 ? menuBar : 24)
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
