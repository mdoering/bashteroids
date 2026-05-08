import AVFoundation

/// Background-music playback. Single shared `AVAudioPlayer` looped on demand;
/// scene-level callers ask for a track in `didMove(to:)` and stop in
/// `willMove(from:)`. Independent of `AudioEngine` (which handles synthesised
/// SFX) so the two don't fight over the same player nodes.
@MainActor
final class MusicPlayer {
    static let shared = MusicPlayer()

    private var player: AVAudioPlayer?
    private var currentResource: String?

    private init() {}

    /// Play a bundled audio file in an infinite loop. If the requested
    /// resource is already playing, this is a no-op (so re-entering the
    /// same scene doesn't restart the loop). `volume` is 0...1 with 1 as
    /// the source-file level; the source files are pre-baked at the gain
    /// the designer wants.
    func play(resource: String, ext: String, volume: Float = 1.0) {
        if currentResource == resource, player?.isPlaying == true {
            return
        }
        stop()
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("MusicPlayer: missing \(resource).\(ext)")
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            currentResource = resource
        } catch {
            print("MusicPlayer: failed to play \(resource).\(ext): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentResource = nil
    }
}
