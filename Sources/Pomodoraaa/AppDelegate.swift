import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

@main
@MainActor
enum PomodoraaaApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let prefs = Prefs()
    let timer = TimerModel()
    let music = MusicPlayer()

    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var bag = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar app, no Dock icon
        buildPanel()
        buildStatusItem()
        registerHotKeys()
        bindModels()
        Feedback.requestPermission()
        showWidget()
    }

    /// Opening the app again (Launchpad, Finder, Spotlight) brings the widget back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWidget()
        return false
    }

    // MARK: Floating widget

    private func buildPanel() {
        let root = WidgetRootView(
            timer: timer, music: music, prefs: prefs,
            onClose: { [weak self] in self?.hideWidget() },
            onSizeChange: { [weak self] size in self?.panel?.fit(contentSize: size) },
            onMoved: { [weak self] in self?.panel?.savePosition() }
        )

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 384, height: 230))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 384, height: 230))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        // Invisible web view that plays YouTube audio, tucked behind the card.
        let web = music.webView
        web.frame = NSRect(x: 40, y: 230 - 24 - 230, width: 230, height: 230)
        web.autoresizingMask = [.maxXMargin, .minYMargin]
        container.addSubview(web)

        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        panel.contentView = container
        self.panel = panel
        panel.restorePosition()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.panel?.ensureOnScreen() }
        }
    }

    func showWidget() {
        panel.ensureOnScreen()
        panel.orderFrontRegardless()
    }

    func hideWidget() {
        panel.savePosition()
        panel.orderOut(nil)
    }

    @objc func toggleWidget() {
        panel.isVisible ? hideWidget() : showWidget()
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Pomodoraaa")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        let active = timer.isRunning || timer.remaining != timer.totalSeconds
        button.title = active ? " \(timer.timeString)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let show = item(panel.isVisible ? "Hide widget" : "Show widget", #selector(toggleWidget), key: "p")
        show.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(show)

        menu.addItem(item("Start focus (\(timer.focusMinutes) min)", #selector(startFocus)))

        let pause = item(timer.isRunning ? "Pause" : "Resume", #selector(toggleTimer), key: " ")
        pause.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(pause)

        menu.addItem(item("Skip to next session", #selector(skip)))
        menu.addItem(item("Reset", #selector(resetTimer)))

        if music.current != nil {
            menu.addItem(item(music.isPlaying ? "Pause music" : "Play music", #selector(toggleMusic)))
        }

        menu.addItem(.separator())

        let templates = NSMenuItem(title: "Template", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for tpl in Templates.all {
            let entry = item(tpl.name, #selector(pickTemplate(_:)))
            entry.representedObject = tpl.id
            entry.state = prefs.templateID == tpl.id ? .on : .off
            sub.addItem(entry)
        }
        templates.submenu = sub
        menu.addItem(templates)

        let compact = item("Minimized pill", #selector(toggleCompact))
        compact.state = prefs.compact ? .on : .off
        menu.addItem(compact)

        menu.addItem(item("Move widget to top-right", #selector(resetPosition)))

        let login = item("Launch at login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quit Pomodoraaa", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func startFocus() {
        timer.startFocus()
        showWidget()
    }

    @objc private func toggleTimer() { timer.toggle() }
    @objc private func skip() { timer.skip() }
    @objc private func resetTimer() { timer.stop() }
    @objc private func toggleMusic() { music.togglePlayPause() }
    @objc private func toggleCompact() { prefs.compact.toggle() }

    @objc private func resetPosition() {
        panel.moveToDefaultSpot()
        panel.savePosition()
        showWidget()
    }

    @objc private func pickTemplate(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { prefs.templateID = id }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func quit() {
        music.stop()
        panel.savePosition()
        NSApp.terminate(nil)
    }

    // MARK: Global shortcuts  (⌃⌥P show/hide · ⌃⌥Space pause/resume)

    private func registerHotKeys() {
        let mods = controlKey | optionKey
        hotKeys = [
            HotKey(id: 1, keyCode: kVK_ANSI_P, modifiers: mods) { [weak self] in self?.toggleWidget() },
            HotKey(id: 2, keyCode: kVK_Space, modifiers: mods) { [weak self] in self?.timer.toggle() },
        ]
    }

    // MARK: Wiring

    private func bindModels() {
        // Menu-bar countdown.
        timer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &bag)

        // Music follows the timer: plays during focus, pauses on pause (and on breaks if chosen).
        Publishers.CombineLatest(timer.$isRunning, timer.$mode)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running, mode in
                self?.music.syncWithTimer(running: running, isBreak: mode.isBreak)
            }
            .store(in: &bag)
    }
}
