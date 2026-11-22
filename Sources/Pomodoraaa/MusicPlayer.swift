import AVFoundation
import Foundation

/// One of the built-in focus tracks.
struct Station: Hashable, Identifiable {
    let track: FocusSynth.Track
    let name: String
    let detail: String
    let symbol: String
    var id: Int { track.rawValue }
}

/// Plays the built-in focus tracks. They're generated live by `FocusSynth` inside the app,
/// so music needs no internet, no account and no other app, and never runs out.
@MainActor
final class MusicPlayer: ObservableObject {
    static let stations: [Station] = [
        Station(track: .lofi, name: "Lofi Study", detail: "Mellow keys, soft beat, vinyl", symbol: "headphones"),
        Station(track: .piano, name: "Piano Drift", detail: "Sparse, calm piano", symbol: "pianokeys"),
        Station(track: .drone, name: "Deep Focus", detail: "Slow ambient pads", symbol: "sparkles"),
        Station(track: .rain, name: "Rain", detail: "Steady rain on glass", symbol: "cloud.rain"),
        Station(track: .ocean, name: "Ocean", detail: "Rolling waves", symbol: "water.waves"),
        Station(track: .brown, name: "Brown Noise", detail: "Deep, steady noise", symbol: "waveform"),
    ]

    private let defaults = UserDefaults.standard

    @Published private(set) var current: Station?
    @Published private(set) var isPlaying = false
    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: "musicVolume")
            if isPlaying { synth?.targetGain = Self.gain(for: volume) }
        }
    }
    @Published var pauseOnBreaks: Bool {
        didSet { defaults.set(pauseOnBreaks, forKey: "pauseOnBreaks") }
    }
    @Published var message: String?

    /// True once the user picked something: music then follows the timer.
    private var wantsMusic = false

    private var engine: AVAudioEngine?
    private var synth: FocusSynth?
    private var stopWork: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        volume = d.object(forKey: "musicVolume") as? Double ?? 60
        pauseOnBreaks = d.object(forKey: "pauseOnBreaks") as? Bool ?? true
        if let raw = d.object(forKey: "lastTrack") as? Int {
            current = Self.stations.first { $0.track.rawValue == raw }
        }
    }

    func isCurrent(_ station: Station) -> Bool { current == station }

    // MARK: Public controls

    /// Tap on a track row: play it, or pause it if it's already playing.
    func tap(_ station: Station) {
        if isCurrent(station) {
            togglePlayPause()
        } else {
            current = station
            defaults.set(station.track.rawValue, forKey: "lastTrack")
            wantsMusic = true
            resumeInternal()
        }
    }

    func togglePlayPause() {
        guard current != nil else { return }
        if isPlaying { wantsMusic = false; pauseInternal() } else { wantsMusic = true; resumeInternal() }
    }

    func stop() {
        wantsMusic = false
        pauseInternal()
        engine?.stop()
    }

    /// Called whenever the timer starts, pauses or switches between focus and break.
    func syncWithTimer(running: Bool, isBreak: Bool) {
        guard wantsMusic, current != nil else { return }
        let shouldPlay = running && !(isBreak && pauseOnBreaks)
        if shouldPlay { resumeInternal() } else { pauseInternal() }
    }

    // MARK: Internals

    private func resumeInternal() {
        guard let current else { return }
        stopWork?.cancel()
        guard let synth = startEngine() else { return }
        synth.requestedTrack = current.track
        synth.targetGain = Self.gain(for: volume)
        isPlaying = true
        message = nil
    }

    /// Fades out, then pauses the audio engine so nothing runs while music is off.
    private func pauseInternal() {
        guard isPlaying else { return }
        synth?.targetGain = 0
        isPlaying = false
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let player = self, !player.isPlaying else { return }
            player.engine?.pause()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func startEngine() -> FocusSynth? {
        if let engine, let synth {
            if !engine.isRunning { try? engine.start() }
            return synth
        }
        let engine = AVAudioEngine()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = rate > 0 ? rate : 48_000
        let synth = FocusSynth(sampleRate: sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let left = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            synth.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            message = "Couldn't start audio output (\(error.localizedDescription))."
            return nil
        }
        self.engine = engine
        self.synth = synth
        return synth
    }

    /// Slider 0–100 to a gentle, roughly perceptual loudness curve.
    private static func gain(for volume: Double) -> Float {
        let v = Float(max(0, min(100, volume)) / 100)
        return v * v * 0.9
    }
}
