import AppKit

/// A borderless, transparent panel that floats above every app and every Space,
/// including full-screen apps, without stealing focus from what you're working on.
final class FloatingPanel: NSPanel {
    static weak var shared: FloatingPanel?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the SwiftUI views draw their own soft shadow
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        FloatingPanel.shared = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Resize to the SwiftUI content with the top edge pinned, so panels open downward.
    /// Horizontally the widget stays anchored to the side of the screen it's on: on the right half
    /// its right edge stays put, on the left half its left edge does. So minimising to the pill or
    /// clock icon (and expanding again) happens in place instead of jumping sideways.
    func fit(contentSize size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let f = frame
        if abs(f.width - size.width) < 0.5 && abs(f.height - size.height) < 0.5 { return }
        let vf = (screen ?? NSScreen.main)?.visibleFrame
        let anchorRight = vf.map { f.midX > $0.midX } ?? false
        var rect = NSRect(x: anchorRight ? f.maxX - size.width : f.minX,
                          y: f.maxY - size.height, width: size.width, height: size.height)
        if let vf {
            // If a tall panel would run off the bottom of the screen, slide the widget up so it stays visible.
            if rect.minY < vf.minY { rect.origin.y = min(vf.minY, vf.maxY - rect.height) }
            // Keep it within the screen sideways too.
            if rect.maxX > vf.maxX { rect.origin.x = vf.maxX - rect.width }
            if rect.minX < vf.minX { rect.origin.x = vf.minX }
        }
        setFrame(rect, display: true)
    }

    // MARK: Position memory

    private static let xKey = "panelX"
    private static let topKey = "panelTop"

    func savePosition() {
        UserDefaults.standard.set(frame.minX, forKey: Self.xKey)
        UserDefaults.standard.set(frame.maxY, forKey: Self.topKey)
    }

    /// Restore the last spot, or start near the top-right corner of the main screen.
    func restorePosition() {
        let d = UserDefaults.standard
        let size = frame.size
        if d.object(forKey: Self.xKey) != nil {
            let x = d.double(forKey: Self.xKey)
            let top = d.double(forKey: Self.topKey)
            let topLeft = NSPoint(x: x + 40, y: top - 40)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(topLeft) }) {
                setFrameOrigin(NSPoint(x: x, y: top - size.height))
                return
            }
        }
        moveToDefaultSpot()
    }

    func moveToDefaultSpot() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(x: vf.maxX - 336 - 48 - 24, y: vf.maxY - size.height))
    }

    /// If the widget ended up off every screen (e.g. a display was unplugged), bring it back.
    func ensureOnScreen() {
        let probe = NSPoint(x: frame.minX + 60, y: frame.maxY - 60)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(probe) }) {
            moveToDefaultSpot()
        }
    }
}
