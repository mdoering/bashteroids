import Foundation

enum GameSettings {
    private static let levelKey   = "bashteroids.lastPlayedLevel"
    private static let modeKey    = "bashteroids.lastMode"

    static var lastPlayedLevel: Int {
        get {
            let raw = UserDefaults.standard.integer(forKey: levelKey)
            return raw == 0 ? 1 : max(1, min(9, raw))
        }
        set { UserDefaults.standard.set(max(1, min(9, newValue)), forKey: levelKey) }
    }

    static var lastMode: GameMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let mode = GameMode(rawValue: raw) else { return .survival }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Powerup density is intentionally session-only: every app launch starts
    /// at .normal, but cycling the selector during a session sticks across
    /// subsequent games until the app quits.
    static var sessionPowerUpDensity: PowerUpDensity = .normal
}
