import Foundation

// Edit this file to retune the level progression. Levels 1...curated.count are
// hand-picked; anything beyond uses the formula in `extrapolated(for:)`.
// Asteroids / UFOs / aliens / snakes count toward level completion. Mines,
// rocks, and power-ups do NOT — they're hazards/loot.

struct LevelConfig {
    let asteroids: Int
    let ufos: Int
    let aliens: Int
    let mines: Int
    let rocks: Int
    let snakes: Int
    let powerUps: Int
}

enum LevelRoster {
    private static let curated: [LevelConfig] = [
        // Level 1
        LevelConfig(asteroids: 4, ufos: 0, aliens: 0, mines: 0, rocks: 0, snakes: 0, powerUps: 0),
        // Level 2
        LevelConfig(asteroids: 5, ufos: 0, aliens: 0, mines: 0, rocks: 0, snakes: 0, powerUps: 1),
        // Level 3
        LevelConfig(asteroids: 6, ufos: 1, aliens: 0, mines: 0, rocks: 0, snakes: 0, powerUps: 1),
        // Level 4
        LevelConfig(asteroids: 7, ufos: 1, aliens: 0, mines: 1, rocks: 0, snakes: 0, powerUps: 1),
        // Level 5
        LevelConfig(asteroids: 8, ufos: 2, aliens: 1, mines: 1, rocks: 0, snakes: 1, powerUps: 2),
        // Level 6
        LevelConfig(asteroids: 9, ufos: 2, aliens: 1, mines: 2, rocks: 1, snakes: 1, powerUps: 2),
    ]

    static func config(for level: Int) -> LevelConfig {
        let l = max(1, level)
        if l <= curated.count { return curated[l - 1] }
        return extrapolated(for: l)
    }

    private static func extrapolated(for level: Int) -> LevelConfig {
        LevelConfig(
            asteroids: 8 + level,
            ufos:      1 + level / 3,
            aliens:        level / 3,
            mines:     1 + level / 3,
            rocks:         level / 4,
            snakes:    1 + level / 6,
            powerUps:  1 + level / 3
        )
    }
}

struct BattleConfig {
    let walls: Int
    let mazeClusters: Int
    let staticAsteroids: Int
}

extension LevelRoster {
    static func battleConfig(for level: Int) -> BattleConfig {
        let l = max(1, min(9, level))
        switch l {
        case 1: return BattleConfig(walls: 3,  mazeClusters: 0, staticAsteroids: 0)
        case 2: return BattleConfig(walls: 4,  mazeClusters: 0, staticAsteroids: 1)
        case 3: return BattleConfig(walls: 5,  mazeClusters: 0, staticAsteroids: 2)
        case 4: return BattleConfig(walls: 5,  mazeClusters: 1, staticAsteroids: 3)
        case 5: return BattleConfig(walls: 6,  mazeClusters: 1, staticAsteroids: 4)
        case 6: return BattleConfig(walls: 7,  mazeClusters: 1, staticAsteroids: 5)
        case 7: return BattleConfig(walls: 8,  mazeClusters: 2, staticAsteroids: 6)
        case 8: return BattleConfig(walls: 9,  mazeClusters: 2, staticAsteroids: 7)
        case 9: return BattleConfig(walls: 10, mazeClusters: 3, staticAsteroids: 8)
        default: return BattleConfig(walls: 3, mazeClusters: 0, staticAsteroids: 0)
        }
    }
}
