import AVFoundation

@MainActor
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat

    private let shootBuffer: AVAudioPCMBuffer
    private let explosionBuffer: AVAudioPCMBuffer
    private let denialBuffer: AVAudioPCMBuffer
    private let thrustLoopBuffer: AVAudioPCMBuffer

    private var oneshotPool: [AVAudioPlayerNode] = []
    private var oneshotIndex = 0

    private var thrustPool: [AVAudioPlayerNode] = []

    private init() {
        format = Synth.standardFormat()
        shootBuffer = Synth.makeShoot(format: format)
        explosionBuffer = Synth.makeExplosion(format: format)
        denialBuffer = Synth.makeDenial(format: format)
        thrustLoopBuffer = Synth.makeThrustLoop(format: format)

        configureSession()
        buildGraph()
        startEngine()
    }

    // MARK: - Public API

    func playShoot() {
        playOneshot(shootBuffer, gain: 0.85)
    }

    func playExplosion() {
        playOneshot(explosionBuffer, gain: 0.95)
    }

    func playDenial() {
        playOneshot(denialBuffer, gain: 0.6)
    }

    func setThrust(playerIndex: Int, on: Bool) {
        guard thrustPool.indices.contains(playerIndex) else { return }
        let node = thrustPool[playerIndex]
        if on {
            if !node.isPlaying {
                node.scheduleBuffer(thrustLoopBuffer, at: nil, options: .loops, completionHandler: nil)
                node.play()
            }
            node.volume = 0.35
        } else if node.isPlaying {
            node.stop()
        }
    }

    func stopAllThrust() {
        for node in thrustPool where node.isPlaying { node.stop() }
    }

    // MARK: - Setup

    private func configureSession() {
        #if os(iOS) || os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioEngine: session configure failed: \(error)")
        }
        #endif
    }

    private func buildGraph() {
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            oneshotPool.append(p)
        }

        // Thrust nodes are created stopped; setThrust schedules + starts the
        // loop on demand and stops the node when thrust ends, so a dead ship
        // can't leave a silent-but-playing loop that resurfaces audibly later.
        for _ in 0..<ControllerManager.maxPlayers {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            p.volume = 0.35
            thrustPool.append(p)
        }
    }

    private func startEngine() {
        engine.prepare()
        do {
            try engine.start()
            for p in oneshotPool { p.play() }
        } catch {
            print("AudioEngine: start failed: \(error)")
        }
    }

    private func playOneshot(_ buffer: AVAudioPCMBuffer, gain: Float) {
        let node = oneshotPool[oneshotIndex]
        oneshotIndex = (oneshotIndex + 1) % oneshotPool.count
        node.volume = gain
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
}
