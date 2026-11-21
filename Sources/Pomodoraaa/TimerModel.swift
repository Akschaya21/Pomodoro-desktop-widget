import AppKit
import SwiftUI
import UserNotifications

/// The pomodoro engine: focus → short break → … → long break.
/// Time is computed from an end date, so it stays accurate even if the Mac is busy.
@MainActor
final class TimerModel: ObservableObject {
    enum Mode: String {
        case focus, shortBreak, longBreak

        var label: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Short break"
            case .longBreak: return "Long break"
            }
        }

        var isBreak: Bool { self != .focus }
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var mode: Mode = .focus
    @Published private(set) var remaining: Int = 25 * 60
    @Published private(set) var isRunning = false
    /// Current focus round, 1…rounds.
    @Published private(set) var round = 1
    /// Shown after the last focus round of a cycle.
    @Published var cycleComplete = false
    /// Focused minutes today.
    @Published private(set) var focusedToday = 0

    @Published var focusMinutes: Int { didSet { durationsChanged(key: "focusMinutes", value: focusMinutes) } }
    @Published var shortMinutes: Int { didSet { durationsChanged(key: "shortMinutes", value: shortMinutes) } }
    @Published var longMinutes: Int { didSet { durationsChanged(key: "longMinutes", value: longMinutes) } }
    @Published var rounds: Int { didSet { defaults.set(rounds, forKey: "rounds") } }
    @Published var autoStart: Bool { didSet { defaults.set(autoStart, forKey: "autoStart") } }

    private var endDate: Date?
    private var ticker: Timer?

    init() {
        let d = UserDefaults.standard
        let focus = d.object(forKey: "focusMinutes") as? Int ?? 25
        focusMinutes = focus
        shortMinutes = d.object(forKey: "shortMinutes") as? Int ?? 5
        longMinutes = d.object(forKey: "longMinutes") as? Int ?? 15
        rounds = d.object(forKey: "rounds") as? Int ?? 4
        autoStart = d.object(forKey: "autoStart") as? Bool ?? true
        remaining = focus * 60

        if d.string(forKey: "focusedDay") == TimerModel.dayKey() {
            focusedToday = d.integer(forKey: "focusedToday")
        }
    }

    // MARK: Derived

    var totalSeconds: Int { minutes(for: mode) * 60 }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remaining) / Double(totalSeconds)))
    }

    var timeString: String { Self.format(remaining) }

    static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func minutes(for mode: Mode) -> Int {
        switch mode {
        case .focus: return focusMinutes
        case .shortBreak: return shortMinutes
        case .longBreak: return longMinutes
        }
    }

    // MARK: Controls

    func start() {
        guard !isRunning else { return }
        cycleComplete = false
        if remaining <= 0 { remaining = totalSeconds }
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        isRunning = true
        startTicker()
    }

    func pause() {
        guard isRunning else { return }
        if let endDate { remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow))) }
        endDate = nil
        isRunning = false
        stopTicker()
    }

    func toggle() { isRunning ? pause() : start() }

    /// Start a fresh focus session from round 1.
    func startFocus() {
        stop()
        start()
    }

    /// Reset to the beginning of a cycle without starting.
    func stop() {
        pause()
        mode = .focus
        round = 1
        cycleComplete = false
        remaining = focusMinutes * 60
    }

    func skip() { advance(natural: false) }

    func applyPreset(focus: Int, short: Int, long: Int) {
        focusMinutes = focus
        shortMinutes = short
        longMinutes = long
    }

    // MARK: Engine

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        let left = Int(ceil(endDate.timeIntervalSinceNow))
        if left <= 0 {
            remaining = 0
            advance(natural: true)
        } else if left != remaining {
            remaining = left
        }
    }

    private func advance(natural: Bool) {
        let wasRunning = isRunning
        let finished = mode
        stopTicker()
        endDate = nil
        isRunning = false

        if finished == .focus, natural {
            addFocused(minutes: focusMinutes)
        }

        switch finished {
        case .focus:
            if round >= rounds {
                mode = .longBreak
                if natural { cycleComplete = true }
            } else {
                mode = .shortBreak
            }
        case .shortBreak:
            round += 1
            mode = .focus
        case .longBreak:
            round = 1
            mode = .focus
        }
        remaining = totalSeconds

        if natural {
            Feedback.sessionEnded(finished: finished, next: mode, cycleComplete: cycleComplete)
        }

        // Keep going automatically unless the full cycle just finished.
        let keepRunning = natural ? (autoStart && !cycleComplete) : wasRunning
        if keepRunning { start() }
    }

    private func durationsChanged(key: String, value: Int) {
        defaults.set(value, forKey: key)
        if !isRunning { remaining = totalSeconds }
    }

    private func addFocused(minutes: Int) {
        let today = Self.dayKey()
        if defaults.string(forKey: "focusedDay") != today {
            focusedToday = 0
            defaults.set(today, forKey: "focusedDay")
        }
        focusedToday += minutes
        defaults.set(focusedToday, forKey: "focusedToday")
    }

    private static func dayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// Chime + notification at the end of a session.
@MainActor
enum Feedback {
    private static var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sessionEnded(finished: TimerModel.Mode, next: TimerModel.Mode, cycleComplete: Bool) {
        NSSound(named: NSSound.Name(finished == .focus ? "Glass" : "Hero"))?.play()
        guard canNotify else { return }

        let content = UNMutableNotificationContent()
        if cycleComplete {
            content.title = "Focus cycle done"
            content.body = "Great work. Time for a long break."
        } else if finished == .focus {
            content.title = "Focus session done"
            content.body = "\(next.label) — stretch, breathe, drink water."
        } else {
            content.title = "Break's over"
            content.body = "Back to focus."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
