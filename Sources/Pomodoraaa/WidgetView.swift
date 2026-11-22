import AppKit
import SwiftUI

enum OpenPanel: Equatable {
    case none, time, music, template
}

/// Root of the floating window: the widget card (or minimized pill) plus the open option panel.
struct WidgetRootView: View {
    @ObservedObject var timer: TimerModel
    @ObservedObject var music: MusicPlayer
    @ObservedObject var prefs: Prefs
    var onClose: () -> Void
    var onSizeChange: (CGSize) -> Void
    var onMoved: () -> Void

    @State private var panel: OpenPanel = .none

    private var look: Look {
        let t = prefs.template
        let breakGlass = t.isGlass && timer.mode.isBreak
        return Look(
            t: t,
            accent: breakGlass ? Templates.breakMint : t.accent,
            onAccent: breakGlass ? Color(hex: 0x0A1C07) : t.onAccent,
            glassTint: prefs.glassTint,
            onBreak: timer.mode.isBreak
        )
    }

    var body: some View {
        content
            .padding(24) // room for the shadow
            .fixedSize()
            .background(
                // Report the content size so the window can grow/shrink to fit (panels open downward).
                GeometryReader { geo in
                    Color.clear
                        .onAppear { onSizeChange(geo.size) }
                        .onChange(of: geo.size) { size in onSizeChange(size) }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.colorScheme, look.t.isLight ? .light : .dark)
    }

    @ViewBuilder
    private var content: some View {
        if prefs.iconMode {
            ClockIconView(timer: timer, look: look)
                .modifier(WindowDrag(tapCount: 1, onDoubleClick: { prefs.iconMode = false }, onDragEnd: onMoved))
        } else if prefs.compact {
            PillView(timer: timer, look: look)
                .modifier(WindowDrag(onDoubleClick: { prefs.compact = false }, onDragEnd: onMoved))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                WidgetCard(timer: timer, music: music, look: look, panel: panel,
                           onClose: onClose,
                           onMinimize: { panel = .none; prefs.iconMode = true },
                           onPanel: toggle)
                    .modifier(WindowDrag(onDoubleClick: { panel = .none; prefs.compact = true }, onDragEnd: onMoved))

                switch panel {
                case .time:
                    TimePanel(timer: timer, look: look, onDone: { panel = .none })
                case .music:
                    MusicPanel(music: music, look: look, onDone: { panel = .none })
                case .template:
                    TemplatePanel(prefs: prefs, look: look, onDone: { panel = .none })
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private func toggle(_ p: OpenPanel) {
        panel = (panel == p) ? .none : p
    }
}

// MARK: Card

struct WidgetCard: View {
    @ObservedObject var timer: TimerModel
    @ObservedObject var music: MusicPlayer
    let look: Look
    let panel: OpenPanel
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onPanel: (OpenPanel) -> Void

    private var t: WidgetTemplate { look.t }

    private var modeTitle: String {
        timer.isRunning ? timer.mode.label : "\(timer.mode.label) · paused"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if timer.cycleComplete {
                completeContent
            } else {
                header
                timeRow
                progressRow
                musicStrip
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 336, alignment: .leading)
        .foregroundStyle(t.text)
        .background(TemplateBackground(template: t, radius: 30, glassTint: look.glassTint, onBreak: look.onBreak))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            CircleIconButton(system: "xmark", size: 22, iconSize: 9, bg: t.button, fg: t.text,
                             help: "Close — keeps running in the menu bar", action: onClose)
            CircleIconButton(system: "minus", size: 22, iconSize: 9, bg: t.button, fg: t.text,
                             help: "Minimise to a clock icon", action: onMinimize)
            Image(systemName: timer.mode.isBreak ? "cup.and.saucer.fill" : "flame.fill")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(look.accent)
            Text(modeTitle)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .lineLimit(1)
            Spacer(minLength: 8)
            optionButton("timer", .time, help: "Edit time")
            optionButton("music.note", .music, help: "Focus music")
            optionButton("paintpalette", .template, help: "Template")
        }
    }

    private func optionButton(_ symbol: String, _ target: OpenPanel, help: String) -> some View {
        let on = panel == target
        return CircleIconButton(system: symbol, size: 30, iconSize: 14,
                                bg: on ? look.accent : t.button, fg: on ? look.onAccent : t.text,
                                help: help) { onPanel(target) }
    }

    private var timeFont: Font {
        t.monospaced
            ? Font.system(size: 56, weight: .regular, design: .monospaced)
            : Font.system(size: 60, weight: t.timeWeight, design: .default)
    }

    private var timeRow: some View {
        HStack(alignment: .center) {
            TickerText(text: timer.timeString, font: timeFont, kerning: -1)
                .foregroundStyle(timer.isRunning ? t.text : t.text.opacity(0.72))
            Spacer(minLength: 8)
            CircleIconButton(system: "forward.end.fill", size: 38, iconSize: 13, bg: t.button, fg: t.text,
                             help: "Skip to next session") { timer.skip() }
            CircleIconButton(system: timer.isRunning ? "pause.fill" : "play.fill", size: 48, iconSize: 18,
                             bg: look.accent, fg: look.onAccent,
                             help: timer.isRunning ? "Pause" : "Start") { timer.toggle() }
        }
    }

    private var progressRow: some View {
        HStack(spacing: 12) {
            TickProgress(progress: timer.progress, fill: look.accent, track: t.track)
            HStack(spacing: 5) {
                ForEach(1...max(1, timer.rounds), id: \.self) { i in
                    Circle()
                        .fill(i <= timer.round ? look.accent : t.track)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var musicStrip: some View {
        if let station = music.current, music.isPlaying {
            HStack(spacing: 8) {
                EqualizerBars(color: look.accent)
                Text(station.name)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                Text("· \(station.detail)")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(t.secondary)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.top, 4)
        }
    }

    private var focusedText: String {
        let m = timer.focusedToday
        if m >= 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min" }
        return "\(m) min"
    }

    private var completeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundStyle(look.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(look.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus cycle done")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                    Text("\(timer.rounds) rounds · \(focusedText) focused today")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(t.secondary)
                }
                Spacer(minLength: 0)
                CircleIconButton(system: "xmark", size: 22, iconSize: 9, bg: t.button, fg: t.text,
                                 help: "Close — keeps running in the menu bar", action: onClose)
            }
            HStack(spacing: 8) {
                Button("Take long break") {
                    timer.cycleComplete = false
                    timer.start()
                }
                .buttonStyle(ChipStyle(bg: look.accent, fg: look.onAccent, expand: true))
                Button("Start again") { timer.startFocus() }
                    .buttonStyle(ChipStyle(bg: t.button, fg: t.text, expand: true))
            }
        }
    }
}

// MARK: Minimized pill

struct PillView: View {
    @ObservedObject var timer: TimerModel
    let look: Look

    var body: some View {
        let t = look.t
        let dot = t.isGlass ? (timer.mode.isBreak ? Templates.breakMint : Color(hex: 0xFF5A1F)) : look.accent
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8)
            TickerText(text: timer.timeString,
                       font: t.monospaced
                           ? Font.system(size: 24, weight: .regular, design: .monospaced)
                           : Font.system(size: 20, weight: .semibold, design: .default))
            Spacer(minLength: 4)
            CircleIconButton(system: timer.isRunning ? "pause.fill" : "play.fill", size: 32, iconSize: 12,
                             bg: look.accent, fg: look.onAccent,
                             help: timer.isRunning ? "Pause" : "Start") { timer.toggle() }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(width: 180)
        .foregroundStyle(t.text)
        .background(TemplateBackground(template: t, radius: 24, glassTint: look.glassTint, onBreak: look.onBreak))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 10)
        .help("Double-click to expand")
    }
}
