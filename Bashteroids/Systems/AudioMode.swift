/// Player-chosen global audio level. Cycled on the title screen and read
/// by AudioEngine (SFX) and MusicPlayer (background music) before producing
/// any sound.
enum AudioMode: String, CaseIterable {
    case music    // background music + SFX (default)
    case effects  // SFX only, no music
    case silence  // muted entirely

    var label: String {
        switch self {
        case .music:   return "MUSIC"
        case .effects: return "EFFECTS"
        case .silence: return "SILENCE"
        }
    }
}
