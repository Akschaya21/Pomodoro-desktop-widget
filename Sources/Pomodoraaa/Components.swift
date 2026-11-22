import AppKit
import SwiftUI

/// Everything a view needs to paint itself in the current template.
struct Look {
    let t: WidgetTemplate
    let accent: Color
    let onAccent: Color
    let glassTint: Double
    let onBreak: Bool
}

// MARK: Backgrounds

/// Frosted, desktop-sampling blur (the "glass").
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }

    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct TemplateBackground: View {
    let template: WidgetTemplate
    let radius: CGFloat
    let glassTint: Double
    var onBreak: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch template.fill {
        case .glass:
            ZStack {
                VisualEffectBlur(cornerRadius: radius)
                    .clipShape(shape)
                shape.fill(Color.white.opacity(glassTint))
                if onBreak {
                    shape.fill(Templates.breakMint.opacity(0.14))
                }
                // Specular rim: bright on top, fading down — the "liquid" edge.
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
        case .glow(let base, let blobs, let rim):
            GeometryReader { geo in
                let side = max(geo.size.width, geo.size.height)
                ZStack {
                    shape.fill(base)
                    ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                        Circle()
                            .fill(RadialGradient(colors: [blob.color, blob.color.opacity(0)],
                                                 center: .center, startRadius: 0, endRadius: side * blob.radius))
                            .frame(width: side * blob.radius * 2, height: side * blob.radius * 2)
                            .position(x: geo.size.width * blob.x, y: geo.size.height * blob.y)
                    }
                    // Soft bright inner edge: the "pillow" bulge from the references.
                    shape.strokeBorder(rim.opacity(0.7), lineWidth: max(4, radius * 0.35))
                        .blur(radius: max(3, radius * 0.3))
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.1), .white.opacity(0.35)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .compositingGroup()
                .clipShape(shape)
            }
        case .solid(let color):
            shape.fill(color)
        case .gradient(let top, let bottom):
            ZStack {
                shape.fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
        }
    }
}

// MARK: Controls

struct CircleIconButton: View {
    let system: String
    var size: CGFloat = 34
    var iconSize: CGFloat = 15
    let bg: Color
    let fg: Color
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: iconSize, weight: .semibold, design: .default))
                .foregroundStyle(fg)
                .frame(width: size, height: size)
                .background(Circle().fill(bg))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct ChipStyle: ButtonStyle {
    var bg: Color
    var fg: Color
    var expand: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .default))
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: expand ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Progress bar from the reference: a solid filled part, the rest drawn as fine ticks.
struct TickProgress: View {
    let progress: Double
    let fill: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(track))
                        x += 6
                    }
                }
                if progress > 0 {
                    Capsule()
                        .fill(fill)
                        .frame(width: max(8, geo.size.width * progress))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .animation(.linear(duration: 0.25), value: progress)
    }
}

/// Little animated bars shown while music plays.
struct EqualizerBars: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: 4 + 8 * abs(sin(t * 3 + Double(i) * 1.3)))
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}

/// A rounded card that hosts one of the three option panels.
struct PanelCard<Content: View>: View {
    let title: String
    let look: Look
    let onDone: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold, design: .default))
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(ChipStyle(bg: look.t.button, fg: look.t.text))
                    .keyboardShortcut(.cancelAction)
            }
            content
        }
        .padding(18)
        .frame(width: 336, alignment: .leading)
        .foregroundStyle(look.t.text)
        .background(TemplateBackground(template: look.t, radius: 26, glassTint: look.glassTint))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(look.t.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 12)
    }
}

/// Drag the floating window from anywhere on a view; double-click to run an action.
struct WindowDrag: ViewModifier {
    var tapCount: Int = 2
    var onDoubleClick: () -> Void
    var onDragEnd: () -> Void
    @State private var start: (mouse: CGPoint, origin: CGPoint)?

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { _ in
                        guard let window = FloatingPanel.shared else { return }
                        let mouse = NSEvent.mouseLocation
                        if start == nil { start = (mouse, window.frame.origin) }
                        guard let s = start else { return }
                        window.setFrameOrigin(NSPoint(x: s.origin.x + mouse.x - s.mouse.x,
                                                      y: s.origin.y + mouse.y - s.mouse.y))
                    }
                    .onEnded { _ in
                        start = nil
                        onDragEnd()
                    }
            )
            .onTapGesture(count: tapCount, perform: onDoubleClick)
    }
}

// MARK: Ticker

/// Text whose characters roll like a ticker when they change (each digit slides in from above
/// as the countdown ticks down). Characters that don't change stay still.
struct TickerText: View {
    let text: String
    let font: Font
    var kerning: CGFloat = 0
    /// true: new characters drop in from the top (counting down); false: rise from the bottom.
    var down: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                TickerChar(char: ch, font: font, kerning: kerning, down: down)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct TickerChar: View {
    let char: Character
    let font: Font
    let kerning: CGFloat
    let down: Bool

    var body: some View {
        ZStack {
            Text(String(char))
                .font(font)
                .monospacedDigit()
                .kerning(kerning)
                .id(char)
                .transition(.asymmetric(
                    insertion: .move(edge: down ? .top : .bottom).combined(with: .opacity),
                    removal: .move(edge: down ? .bottom : .top).combined(with: .opacity)))
        }
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.18),
                                   .init(color: .black, location: 0.82),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: char)
    }
}

// MARK: Clock icon

/// The widget minimised to a small round clock: a progress ring, twelve ticks
/// and a hand that sweeps round as the session runs.
struct ClockIconView: View {
    @ObservedObject var timer: TimerModel
    let look: Look

    var body: some View {
        let t = look.t
        let size: CGFloat = 72
        ZStack {
            TemplateBackground(template: t, radius: size / 2, glassTint: look.glassTint, onBreak: look.onBreak)
            Circle().strokeBorder(t.border, lineWidth: 1)

            // Hour ticks.
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(t.secondary.opacity(i % 3 == 0 ? 0.9 : 0.45))
                    .frame(width: i % 3 == 0 ? 2 : 1.5, height: i % 3 == 0 ? 6 : 4)
                    .offset(y: -size / 2 + 10)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // Progress ring.
            Circle()
                .trim(from: 0, to: max(0.001, timer.progress))
                .stroke(look.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.linear(duration: 0.25), value: timer.progress)

            // Hand.
            Capsule()
                .fill(t.text)
                .frame(width: 2.5, height: size / 2 - 18)
                .offset(y: -(size / 2 - 18) / 2)
                .rotationEffect(.degrees(360 * timer.progress))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: timer.progress)
            Circle().fill(look.accent).frame(width: 7, height: 7)
            Circle().fill(t.text).frame(width: 3, height: 3)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 8)
        .opacity(timer.isRunning ? 1 : 0.85)
        .help("\(timer.mode.label) · \(timer.timeString) — click to expand")
    }
}
