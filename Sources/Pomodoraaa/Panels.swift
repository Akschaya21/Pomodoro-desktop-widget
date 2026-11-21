import SwiftUI

// MARK: 1 · Edit time

struct TimePanel: View {
    @ObservedObject var timer: TimerModel
    let look: Look
    let onDone: () -> Void

    private struct Preset: Hashable {
        let focus: Int, short: Int, long: Int
        var label: String { "\(focus) / \(short)" }
    }

    private let presets = [Preset(focus: 25, short: 5, long: 15),
                           Preset(focus: 50, short: 10, long: 20),
                           Preset(focus: 90, short: 20, long: 30)]

    var body: some View {
        PanelCard(title: "Edit time", look: look, onDone: onDone) {
            StepperRow(label: "Focus", hint: "Deep work block", value: "\(timer.focusMinutes) min", look: look,
                       dec: { timer.focusMinutes = max(5, timer.focusMinutes - 5) },
                       inc: { timer.focusMinutes = min(180, timer.focusMinutes + 5) })
            StepperRow(label: "Short break", hint: "After each focus", value: "\(timer.shortMinutes) min", look: look,
                       dec: { timer.shortMinutes = max(1, timer.shortMinutes - 1) },
                       inc: { timer.shortMinutes = min(30, timer.shortMinutes + 1) })
            StepperRow(label: "Long break", hint: "After the last round", value: "\(timer.longMinutes) min", look: look,
                       dec: { timer.longMinutes = max(5, timer.longMinutes - 5) },
                       inc: { timer.longMinutes = min(60, timer.longMinutes + 5) })
            StepperRow(label: "Rounds", hint: "Before a long break", value: "\(timer.rounds)", look: look,
                       dec: { timer.rounds = max(1, timer.rounds - 1) },
                       inc: { timer.rounds = min(8, timer.rounds + 1) })

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { p in
                    let active = timer.focusMinutes == p.focus && timer.shortMinutes == p.short
                    Button(p.label) { timer.applyPreset(focus: p.focus, short: p.short, long: p.long) }
                        .buttonStyle(ChipStyle(bg: active ? look.accent : look.t.button,
                                               fg: active ? look.onAccent : look.t.text, expand: true))
                }
            }

            Toggle(isOn: $timer.autoStart) {
                Text("Auto-start next session").font(.system(size: 13, weight: .regular, design: .default))
            }
            .toggleStyle(.switch)
            .tint(look.t.isGlass ? .green : look.accent)

            Text("Changes apply to the current session when it's not running.")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(look.t.secondary)
        }
    }
}

struct StepperRow: View {
    let label: String
    let hint: String
    let value: String
    let look: Look
    let dec: () -> Void
    let inc: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 14, weight: .medium, design: .default))
                Text(hint)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(look.t.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                stepButton("minus", help: "Decrease \(label)", action: dec)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .frame(minWidth: 54)
                stepButton("plus", help: "Increase \(label)", action: inc)
            }
            .padding(3)
            .background(Capsule().fill(look.t.button))
        }
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold, design: .default))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: 2 · Focus music

struct MusicPanel: View {
    @ObservedObject var music: MusicPlayer
    let look: Look
    let onDone: () -> Void
    @State private var link = ""

    private var t: WidgetTemplate { look.t }

    private var placeholder: String {
        music.source == .youtube ? "music.youtube.com/playlist?list=…" : "open.spotify.com/playlist/…"
    }

    private var listTitle: String {
        music.recent.contains(where: { $0.source == music.source }) ? "Your links & quick picks" : "Quick picks"
    }

    private var footnote: String {
        music.source == .spotify
            ? "Plays through the Spotify app on this Mac. Music follows the timer: it pauses when you pause."
            : "Plays YouTube / YouTube Music links right inside the widget. Music follows the timer."
    }

    var body: some View {
        PanelCard(title: "Focus music", look: look, onDone: onDone) {
            sourcePicker

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste a playlist, album or track link")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(t.secondary)
                HStack(spacing: 6) {
                    TextField(placeholder, text: $link)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.button))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                        .onSubmit(submit)
                    Button("Play", action: submit)
                        .buttonStyle(ChipStyle(bg: look.accent, fg: look.onAccent))
                }
            }

            if let message = music.message {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(t.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(listTitle)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(t.secondary)

            VStack(spacing: 2) {
                ForEach(music.picksForSource) { station in
                    StationRow(station: station,
                               active: music.isCurrent(station),
                               playing: music.isCurrent(station) && music.isPlaying,
                               look: look) { music.tap(station) }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                Slider(value: $music.volume, in: 0...100)
                    .tint(look.t.isGlass ? .white : look.accent)
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(t.secondary)

            Toggle(isOn: $music.pauseOnBreaks) {
                Text("Pause music on breaks").font(.system(size: 13, weight: .regular, design: .default))
            }
            .toggleStyle(.switch)
            .tint(look.t.isGlass ? .green : look.accent)

            Text(footnote)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(t.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourcePicker: some View {
        HStack(spacing: 0) {
            ForEach(MusicSource.allCases) { source in
                let selected = music.source == source
                Button {
                    music.source = source
                    music.message = nil
                } label: {
                    Text(source.label)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(selected ? look.onAccent : t.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(selected ? look.accent : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.button))
    }

    private func submit() {
        music.play(link: link)
        if music.message == nil { link = "" }
    }
}

struct StationRow: View {
    let station: Station
    let active: Bool
    let playing: Bool
    let look: Look
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(station.name).font(.system(size: 13, weight: .semibold, design: .default))
                    Text(station.detail)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(look.t.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if playing { EqualizerBars(color: look.accent) }
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .foregroundStyle(look.t.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? look.t.button : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Pause \(station.name)" : "Play \(station.name)")
    }
}

// MARK: 3 · Template

struct TemplatePanel: View {
    @ObservedObject var prefs: Prefs
    let look: Look
    let onDone: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        PanelCard(title: "Template", look: look, onDone: onDone) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Templates.all) { tpl in
                    swatch(tpl)
                }
            }

            if look.t.isGlass {
                HStack(spacing: 10) {
                    Text("Glass tint")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(look.t.secondary)
                    Slider(value: $prefs.glassTint, in: 0...0.45)
                        .tint(.white)
                }
            }
        }
    }

    private func swatch(_ tpl: WidgetTemplate) -> some View {
        let selected = prefs.templateID == tpl.id
        return Button {
            prefs.templateID = tpl.id
        } label: {
            VStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("25:00")
                        .font(tpl.monospaced
                              ? Font.system(size: 20, weight: .regular, design: .monospaced)
                              : Font.system(size: 17, weight: .semibold, design: .default))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Capsule().fill(tpl.accent).frame(width: 40, height: 4)
                }
                .foregroundStyle(tpl.text)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 58)
                .background(TemplateBackground(template: tpl, radius: 14, glassTint: prefs.glassTint))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tpl.border, lineWidth: 1))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(selected ? look.accent : Color.clear, lineWidth: 2))

                Text(tpl.name).font(.system(size: 11, weight: .medium, design: .default))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tpl.name) template")
    }
}
