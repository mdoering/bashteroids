import AVFoundation

enum Synth {
    static let sampleRate: Double = 44_100

    static func standardFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    // Short square-wave chirp 880 → 220 Hz over ~0.10 s with a fast attack
    // and quick decay envelope. Pew.
    static func makeShoot(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let duration = 0.10
        let buf = makeBuffer(format: format, duration: duration)
        let ch = buf.floatChannelData![0]
        let frames = Int(buf.frameLength)

        var phase = 0.0
        let f0 = 880.0, f1 = 220.0
        let attack = 0.01
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let freq = f0 + (f1 - f0) * progress
            phase += 2 * .pi * freq / sampleRate
            let square: Float = sin(phase) > 0 ? 0.22 : -0.22
            let env: Float = Float(t < attack
                                   ? t / attack
                                   : max(0, 1 - (t - attack) / (duration - attack)))
            ch[i] = square * env
        }
        return buf
    }

    // Big-boom explosion: a 60 → 30 Hz sine pop transient layered over
    // descending-cutoff filtered noise with a ~0.85 s exponential decay.
    static func makeExplosion(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let duration = 0.85
        let buf = makeBuffer(format: format, duration: duration)
        let ch = buf.floatChannelData![0]
        let frames = Int(buf.frameLength)

        var rng = SeededGenerator(seed: 0xB00B_FEED_FACE)
        var lp1: Float = 0
        var lp2: Float = 0

        let popDuration = 0.045
        let popF0 = 60.0
        let popF1 = 28.0
        var popPhase = 0.0

        let attack = 0.004
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let progress = Float(t / duration)

            var pop: Float = 0
            if t < popDuration {
                let pp = t / popDuration
                let freq = popF0 + (popF1 - popF0) * pp
                popPhase += 2 * .pi * freq / sampleRate
                pop = Float(sin(popPhase)) * Float(1 - pp) * 0.85
            }

            let n = Float.random(in: -1...1, using: &rng)
            let cutoff: Float = max(0.06, 0.45 - progress * 0.35)
            lp1 = lp1 * (1 - cutoff) + n * cutoff
            lp2 = lp2 * (1 - cutoff) + lp1 * cutoff

            let attackEnv: Float = t < attack ? Float(t / attack) : 1
            let decay: Float = Float(exp(-t * 3.4))
            let body = lp2 * attackEnv * decay * 0.95

            ch[i] = pop * Float(exp(-t * 2.5)) + body
        }
        return buf
    }

    // Two short low-pitched "uh-uh" blips — the failed-lock denial cue.
    static func makeDenial(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let blip = 0.07
        let gap  = 0.05
        let duration = blip * 2 + gap
        let buf = makeBuffer(format: format, duration: duration)
        let ch = buf.floatChannelData![0]
        let frames = Int(buf.frameLength)

        let f0 = 240.0
        let attack = 0.005
        var phase = 0.0
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            phase += 2 * .pi * f0 / sampleRate
            let raw: Float = sin(phase) > 0 ? 0.32 : -0.32

            let inFirst  = t < blip
            let inSecond = t >= blip + gap && t < blip + gap + blip
            guard inFirst || inSecond else { ch[i] = 0; continue }

            let local = inFirst ? t : t - (blip + gap)
            let env: Float = local < attack
                ? Float(local / attack)
                : max(0, Float(1 - (local - attack) / (blip - attack)))
            ch[i] = raw * env
        }
        return buf
    }

    // Loopable thrust: ~80 Hz sawtooth + low-pass filtered noise. Loop
    // length is an integer number of saw cycles so the boundary is silent.
    static func makeThrustLoop(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sawFreq = 80.0
        let cycles = 40
        let duration = Double(cycles) / sawFreq
        let buf = makeBuffer(format: format, duration: duration)
        let ch = buf.floatChannelData![0]
        let frames = Int(buf.frameLength)

        var rng = SeededGenerator(seed: 0x7E_55_5E_77E_E)
        var noiseLP: Float = 0
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let phase = (t * sawFreq).truncatingRemainder(dividingBy: 1.0)
            let saw = Float(phase * 2 - 1)
            let n = Float.random(in: -1...1, using: &rng)
            noiseLP = noiseLP * 0.85 + n * 0.15
            ch[i] = saw * 0.20 + noiseLP * 0.55
        }
        return buf
    }

    private static func makeBuffer(format: AVAudioFormat, duration: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buf.frameLength = frameCount
        return buf
    }
}
