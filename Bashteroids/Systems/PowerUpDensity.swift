/// Player-chosen rarity for powerup spawns. Affects both the per-level
/// SURVIVAL count and the BATTLE drip interval.
enum PowerUpDensity: String, CaseIterable {
    case none, low, normal, high, highest

    var label: String {
        switch self {
        case .none:    return "NONE"
        case .low:     return "LOW"
        case .normal:  return "NORMAL"
        case .high:    return "HIGH"
        case .highest: return "HIGHEST"
        }
    }

    /// Multiplier applied to the base spawn count (SURVIVAL) and to the
    /// inverse of the drip interval (BATTLE). 0 for `.none` disables
    /// powerup spawns entirely.
    var multiplier: Double {
        switch self {
        case .none:    return 0
        case .low:     return 0.5
        case .normal:  return 1.0
        case .high:    return 2.0
        case .highest: return 4.0
        }
    }
}
