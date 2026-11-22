import SwiftUI

/// Look-and-feel preferences, persisted in UserDefaults.
@MainActor
final class Prefs: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var templateID: String {
        didSet { defaults.set(templateID, forKey: "templateID") }
    }

    /// 0…1 — how milky the glass template is.
    @Published var glassTint: Double {
        didSet { defaults.set(glassTint, forKey: "glassTint") }
    }

    /// Minimized "pill" mode.
    @Published var compact: Bool {
        didSet { defaults.set(compact, forKey: "compact") }
    }

    /// Minimised to a small clock icon.
    @Published var iconMode: Bool {
        didSet { defaults.set(iconMode, forKey: "iconMode") }
    }

    init() {
        let d = UserDefaults.standard
        templateID = d.string(forKey: "templateID") ?? "glass"
        glassTint = d.object(forKey: "glassTint") as? Double ?? 0.12
        compact = d.bool(forKey: "compact")
        iconMode = d.bool(forKey: "iconMode")
    }

    var template: WidgetTemplate { Templates.named(templateID) }
}
