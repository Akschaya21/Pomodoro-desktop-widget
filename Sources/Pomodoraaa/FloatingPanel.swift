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

    /// Resize to the SwiftUI content while keeping the top-left corner pinned,
    /// so panels open downward and the widget never jumps.
    func fit(contentSize size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let f = frame
        if abs(f.width - size.width) < 0.5 && abs(f.height - size.height) < 0.5 { return }
        setFrame(NSRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
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
