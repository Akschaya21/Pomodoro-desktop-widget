import AVFoundation

/// Generates the built-in focus tracks live, sample by sample. Nothing is streamed or loaded
/// from disk: every track is synthesised on the audio thread, so it plays offline and never ends.
///
/// The main thread only writes `requestedTrack` and `targetGain`; the audio thread fades out,
/// switches track at silence and fades back in, so changes never click.
final class FocusSynth {
    enum Track: Int, CaseIterable {
        case lofi, piano, drone, rain, ocean, brown
    }

    // MARK: Controls (written from the main thread)

    var requestedTrack: Track = .lofi
    var targetGain: Float = 0

    // MARK: State (audio thread only)

    private let sr: Float
    private var track: Track?
    private var gain: Float = 0
    private let gainStep: Float
    private var rng: UInt32 = 0x9E37_79B9
    private var clock = 0 // samples since the track started

    // Noise colours.
    private var brown: Float = 0
    private var pink = [Float](repeating: 0, count: 7)

    // Filters.
    private var lp1: Float = 0, lp2: Float = 0, hp1: Float = 0, hpIn: Float = 0
    private var hatLP: Float = 0, snareHP: Float = 0, snareIn: Float = 0, crackleLP: Float = 0

    // Voices.
    private struct Voice {
        var active = false
        var kind = Kind.ep
        var freq: Float = 0
        var ph: Float = 0
        var ph2: Float = 0
        var amp: Float = 0
        var env: Float = 0
        var attackInc: Float = 0
        var attackLeft = 0
        var decay: Float = 1
        var wait = 0
        var pitchEnv: Float = 0
        var pan: Float = 0.5

        enum Kind { case ep, piano, pad, drop, kick, bass }
    }
    private var voices = [Voice](repeating: Voice(), count: 40)

    // Sequencers.
    private var nextStep = 0          // lofi: sample index of the next 8th-note step
    private var step = 0
    private var snareEnv: Float = 0, hatEnv: Float = 0, crackle: Float = 0
    private var nextEvent = 0         // piano / drone: sample index of the next event
    private var chordIndex = 0
    private var swellPhase: Float = 0, swellRate: Float = 0

    // Small stereo reverb (Schroeder: 4 combs + 2 allpasses per side).
    private struct Comb { var buf: [Float]; var i = 0; var store: Float = 0 }
    private struct AllPass { var buf: [Float]; var i = 0 }
    private var combsL: [Comb], combsR: [Comb], apL: [AllPass], apR: [AllPass]
    private var reverbMix: Float = 0.25
    /// Per-track make-up gain so every track sits at about the same loudness (~ -22 dBFS at volume 60).
    private var level: Float = 1
    private var reverbFeedback: Float = 0.8

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        gainStep = 1 - expf(-1 / (0.12 * Float(sampleRate)))
        let scale = Float(sampleRate) / 44_100
        func comb(_ n: Int) -> Comb { Comb(buf: [Float](repeating: 0, count: Int(Float(n) * scale))) }
        func ap(_ n: Int) -> AllPass { AllPass(buf: [Float](repeating: 0, count: Int(Float(n) * scale))) }
        combsL = [comb(1116), comb(1188), comb(1277), comb(1356)]
        combsR = [comb(1139), comb(1211), comb(1300), comb(1379)]
        apL = [ap(556), ap(441)]
        apR = [ap(579), ap(464)]
    }

    // MARK: Render

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        for n in 0..<frames {
            // Fade to silence before switching tracks, then fade the new one in.
            let switching = track != requestedTrack
            let target = switching ? 0 : targetGain
            gain += (target - gain) * gainStep
            if switching && gain < 0.0005 { start(requestedTrack) }

            var l: Float = 0, r: Float = 0
            if gain > 0.00001, let track {
                (l, r) = sample(track)
                let (wl, wr) = reverb(l, r)
                l = tanhf((l + wl * reverbMix) * gain * level)
                r = tanhf((r + wr * reverbMix) * gain * level)
            }
            left[n] = l
            right?[n] = r
            clock += 1
        }
    }

    private func start(_ t: Track) {
        track = t
        clock = 0
        for i in voices.indices { voices[i].active = false }
        for i in combsL.indices {
            for j in combsL[i].buf.indices { combsL[i].buf[j] = 0 }
            for j in combsR[i].buf.indices { combsR[i].buf[j] = 0 }
        }
        snareEnv = 0; hatEnv = 0; crackle = 0
        nextStep = 0; step = 0; nextEvent = 0; chordIndex = 0
        swellPhase = 0; swellRate = 1 / (9 * sr)
        switch t {
        case .lofi: reverbMix = 0.22; reverbFeedback = 0.78; level = 2.24
        case .piano: reverbMix = 0.55; reverbFeedback = 0.86; level = 1.58
        case .drone: reverbMix = 0.6; reverbFeedback = 0.88; level = 4.3
        case .rain: reverbMix = 0.12; reverbFeedback = 0.75; level = 5.3
        case .ocean: reverbMix = 0.12; reverbFeedback = 0.75; level = 2.7
        case .brown: reverbMix = 0.12; reverbFeedback = 0.75; level = 1.9
        }
    }

    private func sample(_ t: Track) -> (Float, Float) {
        switch t {
        case .lofi: return lofi()
        case .piano: return pianoDrift()
        case .drone: return drone()
        case .rain: return rain()
        case .ocean: return ocean()
        case .brown: return brownNoise()
        }
    }

    // MARK: Tracks

    /// Lofi Study: mellow electric-piano chords, bass, a soft boom-bap beat and vinyl crackle.
    private func lofi() -> (Float, Float) {
        let bpm: Float = 74
        let stepLen = Int(sr * 60 / bpm / 2) // 8th notes
        if clock >= nextStep {
            let chords: [[Int]] = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]]
            let bar = (step / 8) % chords.count
            let s = step % 8
            let chord = chords[bar]
            if s == 0 {
                for (i, note) in chord.enumerated() {
                    trigger(.ep, midi: note, amp: 0.10, attack: 0.008, tau: 1.6,
                            wait: Int(Float(i) * 0.022 * sr), pan: 0.35 + 0.1 * Float(i))
                }
            }
            if s == 0 || s == 4 { trigger(.bass, midi: chord[0] - 12, amp: 0.22, attack: 0.01, tau: 0.6) }
            if s == 0 || s == 3 || s == 5 { trigger(.kick, midi: 0, amp: s == 0 ? 0.55 : 0.4, attack: 0.001, tau: 0.16) }
            if s == 2 || s == 6 { snareEnv = 1 }
            hatEnv = s % 2 == 0 ? 0.9 : 0.55
            if s % 2 == 1 && random() < 0.28 {
                let scale = [0, 3, 5, 7, 10]
                let note = 72 + scale[Int(random() * Float(scale.count)) % scale.count]
                trigger(.ep, midi: note, amp: 0.05, attack: 0.006, tau: 0.9, pan: 0.65)
            }
            step += 1
            // Swing: every second 8th lands a little late.
            nextStep += step % 2 == 1 ? Int(Float(stepLen) * 1.16) : Int(Float(stepLen) * 0.84)
        }

        var (l, r) = voiceMix()

        // Snare: band-limited noise burst. Hat: high noise tick.
        let w = white()
        snareHP = 0.95 * (snareHP + w - snareIn); snareIn = w
        snareEnv *= decayPerSample(0.07)
        hatLP += 0.5 * (w - hatLP)
        hatEnv *= decayPerSample(0.018)
        let drums = snareHP * snareEnv * 0.16 + (w - hatLP) * hatEnv * 0.035
        l += drums; r += drums

        // Warm the whole thing up (lofi = soft top end).
        lp1 += onePole(2600) * (l - lp1)
        lp2 += onePole(2600) * (r - lp2)
        l = lp1; r = lp2

        // Vinyl: hiss plus the odd crackle.
        if random() < 0.00012 { crackle = (0.05 + 0.15 * random()) * (random() < 0.5 ? -1 : 1) }
        crackle *= 0.86
        crackleLP += 0.3 * (white() - crackleLP)
        let vinyl = crackle + crackleLP * 0.006
        return (l + vinyl, r + vinyl)
    }

    /// Piano Drift: sparse, unhurried pentatonic piano notes over a quiet low drone.
    private func pianoDrift() -> (Float, Float) {
        if clock >= nextEvent {
            let scale = [0, 2, 4, 7, 9]
            let octave = 60 + 12 * Int(random() * 2)
            let note = octave + scale[Int(random() * Float(scale.count)) % scale.count]
            trigger(.piano, midi: note, amp: 0.16, attack: 0.004, tau: 1.8, pan: 0.3 + 0.4 * random())
            if random() < 0.35 { trigger(.piano, midi: note - (random() < 0.5 ? 5 : 3), amp: 0.09, attack: 0.004, tau: 1.6, wait: Int(0.18 * sr), pan: 0.4) }
            if chordIndex % 8 == 0 {
                trigger(.pad, midi: 36, amp: 0.05, attack: 3, tau: 8)
                trigger(.pad, midi: 43, amp: 0.035, attack: 3, tau: 8)
            }
            chordIndex += 1
            nextEvent = clock + Int((0.7 + 1.8 * random()) * sr)
        }
        return voiceMix()
    }

    /// Deep Focus: slow, evolving pad chords that drift between four harmonies.
    private func drone() -> (Float, Float) {
        if clock >= nextEvent {
            let chords: [[Int]] = [[45, 52, 57, 60, 64], [41, 48, 57, 60, 65], [43, 50, 55, 59, 62], [40, 47, 55, 59, 64]]
            let chord = chords[chordIndex % chords.count]
            for (i, note) in chord.enumerated() {
                trigger(.pad, midi: note, amp: i == 0 ? 0.07 : 0.045, attack: 3.5, tau: 6, pan: 0.2 + 0.15 * Float(i))
            }
            chordIndex += 1
            nextEvent = clock + Int(12 * sr)
        }
        var (l, r) = voiceMix()
        let bed = nextBrown() * 0.025
        l += bed; r += bed
        return (l, r)
    }

    /// Rain: steady filtered rainfall with individual drops ticking on glass.
    private func rain() -> (Float, Float) {
        let p = nextPink()
        hp1 = 0.97 * (hp1 + p - hpIn); hpIn = p
        let wobble = 0.5 + 0.5 * sinf(Float(clock) / sr * 0.15)
        lp1 += onePole(3500 + 2500 * wobble) * (hp1 - lp1)
        let rumble = nextBrown() * 0.12
        if random() < 0.0004 {
            trigger(.drop, midi: 0, amp: 0.02 + 0.05 * random(), attack: 0.0005, tau: 0.012,
                    freq: 1800 + 3000 * random(), pan: random())
        }
        let (dl, dr) = voiceMix()
        let bed = lp1 * 0.32 + rumble
        return (bed + dl, bed * 0.96 + dr + white() * 0.004)
    }

    /// Ocean: waves rolling in and out every eight to twelve seconds.
    private func ocean() -> (Float, Float) {
        swellPhase += swellRate
        if swellPhase >= 1 { swellPhase -= 1; swellRate = 1 / ((8 + 4 * random()) * sr) }
        let swell = 0.5 - 0.5 * cosf(2 * .pi * swellPhase)
        let noise = nextBrown() * 0.6 + nextPink() * 0.4
        lp1 += onePole(250 + 2600 * powf(swell, 1.6)) * (noise - lp1)
        let v = lp1 * (0.18 + 0.75 * swell)
        lp2 += onePole(400) * (white() - lp2)
        return (v, v * 0.94 + lp2 * 0.02 * swell)
    }

    /// Brown Noise: deep, steady masking noise.
    private func brownNoise() -> (Float, Float) {
        lp1 += onePole(900) * (nextBrown() - lp1)
        lp2 += onePole(900) * (nextBrown() - lp2)
        return (lp1 * 0.7, lp2 * 0.7)
    }

    // MARK: Voices

    private func trigger(_ kind: Voice.Kind, midi: Int, amp: Float, attack: Float, tau: Float,
                         wait: Int = 0, freq: Float? = nil, pan: Float = 0.5) {
        guard let i = voices.firstIndex(where: { !$0.active }) ?? quietestVoice() else { return }
        var v = Voice()
        v.active = true
        v.kind = kind
        v.freq = freq ?? 440 * powf(2, Float(midi - 69) / 12)
        v.amp = amp
        v.attackLeft = max(1, Int(attack * sr))
        v.attackInc = 1 / Float(v.attackLeft)
        v.decay = decayPerSample(tau)
        v.wait = wait
        v.pitchEnv = 1
        v.pan = pan
        // Pads don't start in phase, so stacked notes don't thump.
        v.ph = random() * 2 * .pi
        v.ph2 = random() * 2 * .pi
        voices[i] = v
    }

    private func quietestVoice() -> Int? {
        voices.indices.min { voices[$0].env < voices[$1].env }
    }

    private func voiceMix() -> (Float, Float) {
        var l: Float = 0, r: Float = 0
        let twoPi: Float = 2 * .pi
        for i in voices.indices where voices[i].active {
            if voices[i].wait > 0 { voices[i].wait -= 1; continue }
            var v = voices[i]
            if v.attackLeft > 0 {
                v.env += v.attackInc; v.attackLeft -= 1
            } else {
                v.env *= v.decay
                if v.env < 0.0002 { voices[i].active = false; continue }
            }
            var f = v.freq
            var s: Float
            switch v.kind {
            case .ep:
                // Soft electric piano: sine plus a quickly fading bell partial, gentle tremolo.
                s = sinf(v.ph) + 0.22 * sinf(2 * v.ph) * v.env + 0.05 * sinf(3 * v.ph) * v.env * v.env
                s *= 1 - 0.08 * (0.5 + 0.5 * sinf(Float(clock) / sr * 2 * .pi * 4.5))
            case .piano:
                s = sinf(v.ph) + 0.45 * sinf(2 * v.ph) * v.env + 0.18 * sinf(3 * v.ph) * v.env * v.env
                    + 0.06 * sinf(4.02 * v.ph) * v.env * v.env
            case .pad:
                // Two slightly detuned oscillators with a touch of overtone, slowly breathing.
                v.ph2 += twoPi * f * 1.004 / sr
                if v.ph2 > twoPi { v.ph2 -= twoPi }
                s = 0.6 * sinf(v.ph) + 0.6 * sinf(v.ph2) + 0.12 * sinf(2 * v.ph)
                s *= 0.85 + 0.15 * sinf(Float(clock) / sr * 0.3 + v.pan * 4)
            case .drop:
                v.pitchEnv *= 0.9996
                f *= 0.7 + 0.3 * v.pitchEnv
                s = sinf(v.ph)
            case .kick:
                v.pitchEnv *= decayPerSample(0.03)
                f = 48 + 90 * v.pitchEnv
                s = sinf(v.ph)
            case .bass:
                s = sinf(v.ph) + 0.15 * sinf(2 * v.ph)
            }
            v.ph += twoPi * f / sr
            if v.ph > twoPi { v.ph -= twoPi }
            let out = s * v.env * v.amp
            l += out * (1 - v.pan) * 2 * 0.7071
            r += out * v.pan * 2 * 0.7071
            voices[i] = v
        }
        return (l, r)
    }

    // MARK: Reverb

    private func reverb(_ l: Float, _ r: Float) -> (Float, Float) {
        let input = (l + r) * 0.5 * 0.4
        var outL: Float = 0, outR: Float = 0
        for i in combsL.indices {
            outL += combStep(&combsL[i], input)
            outR += combStep(&combsR[i], input)
        }
        for i in apL.indices {
            outL = allPassStep(&apL[i], outL)
            outR = allPassStep(&apR[i], outR)
        }
        return (outL, outR)
    }

    private func combStep(_ c: inout Comb, _ x: Float) -> Float {
        let y = c.buf[c.i]
        c.store = y * 0.75 + c.store * 0.25 // damping
        c.buf[c.i] = x + c.store * reverbFeedback
        c.i += 1
        if c.i >= c.buf.count { c.i = 0 }
        return y
    }

    private func allPassStep(_ a: inout AllPass, _ x: Float) -> Float {
        let b = a.buf[a.i]
        a.buf[a.i] = x + b * 0.5
        a.i += 1
        if a.i >= a.buf.count { a.i = 0 }
        return b - x
    }

    // MARK: Helpers

    @inline(__always) private func white() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) / Float(Int32.max)
    }

    @inline(__always) private func random() -> Float { white() * 0.5 + 0.5 }

    private func nextBrown() -> Float {
        brown = (brown + 0.02 * white()) / 1.02
        return brown * 3.5
    }

    /// Paul Kellet's pink-noise filter.
    private func nextPink() -> Float {
        let w = white()
        pink[0] = 0.99886 * pink[0] + w * 0.0555179
        pink[1] = 0.99332 * pink[1] + w * 0.0750759
        pink[2] = 0.96900 * pink[2] + w * 0.1538520
        pink[3] = 0.86650 * pink[3] + w * 0.3104856
        pink[4] = 0.55000 * pink[4] + w * 0.5329522
        pink[5] = -0.7616 * pink[5] - w * 0.0168980
        let out = pink[0] + pink[1] + pink[2] + pink[3] + pink[4] + pink[5] + pink[6] + w * 0.5362
        pink[6] = w * 0.115926
        return out * 0.11
    }

    @inline(__always) private func onePole(_ cutoff: Float) -> Float {
        1 - expf(-2 * .pi * cutoff / sr)
    }

    /// Per-sample multiplier for an exponential decay with time constant `tau` seconds.
    @inline(__always) private func decayPerSample(_ tau: Float) -> Float {
        expf(-1 / (tau * sr))
    }
}
