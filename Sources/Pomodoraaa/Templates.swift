import SwiftUI

/// A visual look for the widget. Inspired by the reference widget sets:
/// frosted glass, dark gradients with bright progress, flat bold tiles, paper and pixel LCD.
struct WidgetTemplate: Identifiable, Equatable {
    /// A soft blob of coloured light inside a glow template. Positions are 0…1 of the card.
    struct Blob: Equatable {
        let color: Color
        let x: Double
        let y: Double
        let radius: Double // fraction of the card's larger side
    }

    enum Fill: Equatable {
        case glass
        case solid(Color)
        case gradient(Color, Color)
        /// Luminous "pillow" card: a base colour, blurred light blobs and a bright inner rim.
        case glow(base: Color, blobs: [Blob], rim: Color)
    }

    let id: String
    let name: String
    let fill: Fill
    let text: Color
    let secondary: Color
    let accent: Color
    let onAccent: Color
    let track: Color
    let button: Color
    let border: Color
    let monospaced: Bool
    let timeWeight: Font.Weight

    var isGlass: Bool { fill == .glass }

    /// Light templates need dark menus / controls.
    var isLight: Bool {
        switch id {
        case "sunny", "paper", "pixel": return true
        default: return false
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Templates {
    static let all: [WidgetTemplate] = [
        WidgetTemplate(
            id: "glass", name: "Liquid Glass", fill: .glass,
            text: .white, secondary: .white.opacity(0.78), accent: .white, onAccent: Color(hex: 0x111111),
            track: .white.opacity(0.35), button: .white.opacity(0.18), border: .white.opacity(0.38),
            monospaced: false, timeWeight: .semibold),
        WidgetTemplate(
            id: "bloom", name: "Bloom",
            fill: .glow(base: Color(hex: 0xFF5FB0), blobs: [
                .init(color: Color(hex: 0xFF1F7A), x: 0.85, y: 0.05, radius: 0.55),
                .init(color: Color(hex: 0xFFE066), x: 0.2, y: 1.0, radius: 0.6),
                .init(color: Color(hex: 0xFFF4FA), x: 0.45, y: 0.55, radius: 0.35),
            ], rim: .white),
            text: .white, secondary: .white.opacity(0.85), accent: .white, onAccent: Color(hex: 0xD6246E),
            track: .white.opacity(0.4), button: .white.opacity(0.22), border: .white.opacity(0.45),
            monospaced: false, timeWeight: .regular),
        WidgetTemplate(
            id: "aurora", name: "Aurora",
            fill: .glow(base: Color(hex: 0x9DB8FF), blobs: [
                .init(color: Color(hex: 0xFF3D7F), x: 0.45, y: 0.15, radius: 0.45),
                .init(color: Color(hex: 0xFF8A5C), x: 0.5, y: 0.45, radius: 0.3),
                .init(color: Color(hex: 0xE7EEFF), x: 0.15, y: 0.95, radius: 0.45),
            ], rim: .white),
            text: .white, secondary: .white.opacity(0.85), accent: .white, onAccent: Color(hex: 0xC4285E),
            track: .white.opacity(0.4), button: .white.opacity(0.22), border: .white.opacity(0.5),
            monospaced: false, timeWeight: .medium),
        WidgetTemplate(
            id: "neon", name: "Neon",
            fill: .glow(base: Color(hex: 0x37D11F), blobs: [
                .init(color: Color(hex: 0x031A03), x: 0.5, y: 0.55, radius: 0.5),
                .init(color: Color(hex: 0x0A3A07), x: 0.5, y: 0.5, radius: 0.65),
            ], rim: Color(hex: 0xB8FF9E)),
            text: .white, secondary: Color(hex: 0xC8FFB5), accent: Color(hex: 0x6BFF45), onAccent: Color(hex: 0x062206),
            track: Color(hex: 0x6BFF45, alpha: 0.35), button: .white.opacity(0.12), border: Color(hex: 0x8CFF6A, alpha: 0.45),
            monospaced: true, timeWeight: .regular),
        WidgetTemplate(
            id: "ultraviolet", name: "Ultraviolet",
            fill: .glow(base: Color(hex: 0xA54BF5), blobs: [
                .init(color: Color(hex: 0xF79BFF), x: 0.55, y: 0.0, radius: 0.55),
                .init(color: Color(hex: 0x1C0B3A), x: 0.45, y: 0.95, radius: 0.5),
            ], rim: Color(hex: 0xF3C9FF)),
            text: .white, secondary: Color(hex: 0xEED6FF), accent: .white, onAccent: Color(hex: 0x6A1FB8),
            track: .white.opacity(0.35), button: .white.opacity(0.18), border: Color(hex: 0xF3C9FF, alpha: 0.5),
            monospaced: false, timeWeight: .medium),
        WidgetTemplate(
            id: "ember", name: "Ember", fill: .gradient(Color(hex: 0x8A2F12), Color(hex: 0x3B0E05)),
            text: .white, secondary: Color(hex: 0xFFB79C), accent: Color(hex: 0xFF5A1F), onAccent: .white,
            track: Color(hex: 0xFF7846, alpha: 0.45), button: .white.opacity(0.12), border: Color(hex: 0xFF8C5A, alpha: 0.35),
            monospaced: false, timeWeight: .semibold),
        WidgetTemplate(
            id: "forest", name: "Forest", fill: .gradient(Color(hex: 0x1F5216), Color(hex: 0x0A1C07)),
            text: .white, secondary: Color(hex: 0xB4E3A6), accent: Color(hex: 0x46E02A), onAccent: Color(hex: 0x0A1C07),
            track: Color(hex: 0x78DC5A, alpha: 0.4), button: .white.opacity(0.12), border: Color(hex: 0x78DC5A, alpha: 0.3),
            monospaced: false, timeWeight: .semibold),
        WidgetTemplate(
            id: "tide", name: "Tide", fill: .gradient(Color(hex: 0x1A3F94), Color(hex: 0x0A1538)),
            text: .white, secondary: Color(hex: 0xB8CCFF), accent: Color(hex: 0x3B82FF), onAccent: .white,
            track: Color(hex: 0x78A0FF, alpha: 0.45), button: .white.opacity(0.12), border: Color(hex: 0x78A0FF, alpha: 0.35),
            monospaced: false, timeWeight: .semibold),
        WidgetTemplate(
            id: "sunny", name: "Sunny", fill: .solid(Color(hex: 0xFFD60A)),
            text: Color(hex: 0x111111), secondary: Color(hex: 0x111111, alpha: 0.72), accent: Color(hex: 0x111111), onAccent: Color(hex: 0xFFD60A),
            track: Color(hex: 0x111111, alpha: 0.3), button: Color(hex: 0x111111, alpha: 0.1), border: .black.opacity(0.1),
            monospaced: false, timeWeight: .medium),
        WidgetTemplate(
            id: "paper", name: "Paper", fill: .solid(Color(hex: 0xF5F4EF)),
            text: Color(hex: 0x111111), secondary: Color(hex: 0x555555), accent: Color(hex: 0xE8331B), onAccent: .white,
            track: Color(hex: 0x111111, alpha: 0.22), button: Color(hex: 0x111111, alpha: 0.07), border: .black.opacity(0.08),
            monospaced: false, timeWeight: .medium),
        WidgetTemplate(
            id: "pixel", name: "Pixel", fill: .solid(Color(hex: 0xC5D0A0)),
            text: Color(hex: 0x25331A), secondary: Color(hex: 0x4A5A35), accent: Color(hex: 0x25331A), onAccent: Color(hex: 0xC5D0A0),
            track: Color(hex: 0x25331A, alpha: 0.35), button: Color(hex: 0x25331A, alpha: 0.12), border: Color(hex: 0x25331A, alpha: 0.3),
            monospaced: true, timeWeight: .regular),
        WidgetTemplate(
            id: "midnight", name: "Midnight", fill: .solid(Color(hex: 0x050505)),
            text: .white, secondary: Color(hex: 0xA3A3A3), accent: Color(hex: 0xFF2D2D), onAccent: .white,
            track: .white.opacity(0.28), button: .white.opacity(0.1), border: .white.opacity(0.14),
            monospaced: false, timeWeight: .bold),
    ]

    static func named(_ id: String) -> WidgetTemplate {
        all.first { $0.id == id } ?? all[0]
    }

    /// Mint accent used by the glass template during breaks.
    static let breakMint = Color(hex: 0xB9FFAB)
}
