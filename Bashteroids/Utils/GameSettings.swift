import Foundation

enum GameSettings {
    private static let levelKey   = "bashteroids.lastPlayedLevel"
    private static let modeKey    = "bashteroids.lastMode"
    private static let densityKey = "bashteroids.lastPowerUpDensity"

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

    static var lastPowerUpDensity: PowerUpDensity {
        get {
            guard let raw = UserDefaults.standard.string(forKey: densityKey),
                  let value = PowerUpDensity(rawValue: raw) else { return .normal }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: densityKey) }
    }
}
