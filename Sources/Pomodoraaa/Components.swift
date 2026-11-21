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
            .onTapGesture(count: 2, perform: onDoubleClick)
    }
}

struct SizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
