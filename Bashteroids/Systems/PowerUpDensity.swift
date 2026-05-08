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

    /// Score multiplier — the inverse of the spawn multiplier so that fewer
    /// powerups means a larger score reward. `.none` is capped at the same
    /// 4× as the inverse of `.highest` (the actual inverse of 0 is undefined).
    var scoreMultiplier: Double {
        switch self {
        case .none:    return 4.0
        case .low:     return 2.0
        case .normal:  return 1.0
        case .high:    return 0.5
        case .highest: return 0.25
        }
    }

    /// Human-readable form of `scoreMultiplier` for the game-over screen.
    /// Returns nil for `.normal` (no calculation worth showing).
    var scoreMultiplierDisplay: String? {
        switch self {
        case .none:    return "× 4"
        case .low:     return "× 2"
        case .normal:  return nil
        case .high:    return "÷ 2"
        case .highest: return "÷ 4"
        }
    }
}
