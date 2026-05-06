import AVFoundation

@MainActor
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat

    private let shootBuffer: AVAudioPCMBuffer
    private let explosionBuffer: AVAudioPCMBuffer
    private let thrustLoopBuffer: AVAudioPCMBuffer

    private var oneshotPool: [AVAudioPlayerNode] = []
    private var oneshotIndex = 0

    private var thrustPool: [AVAudioPlayerNode] = []

    private init() {
        format = Synth.standardFormat()
        shootBuffer = Synth.makeShoot(format: format)
        explosionBuffer = Synth.makeExplosion(format: format)
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

    func setThrust(playerIndex: Int, on: Bool) {
        guard thrustPool.indices.contains(playerIndex) else { return }
        let node = thrustPool[playerIndex]
        if !node.isPlaying { node.play() }
        node.volume = on ? 0.35 : 0
    }

    func stopAllThrust() {
        for node in thrustPool { node.volume = 0 }
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

        for _ in 0..<ControllerManager.maxPlayers {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            p.scheduleBuffer(thrustLoopBuffer, at: nil, options: .loops, completionHandler: nil)
            p.volume = 0
            thrustPool.append(p)
        }
    }

    private func startEngine() {
        engine.prepare()
        do {
            try engine.start()
            for p in oneshotPool { p.play() }
            for p in thrustPool { p.play() }
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
