#if DEBUG
import SpriteKit
import GameController

// Advanced/cheat mode: spawn-on-keystroke for testing.
//
// Number keys spawn an entity from a random screen edge:
//   1 = asteroid, 2 = UFO, 3 = mine (interior), 4 = rock, 5 = alien monster, 6 = snake
// Shift+number drops a power-up that drifts inward from a random edge:
//   Shift+1 = shield, Shift+2 = twin-laser, Shift+3 = boost,
//   Shift+4 = minelayer, Shift+5 = torpedo
//
// Compiled out of Release builds via #if DEBUG.
extension GameScene {

    func debugHandleKey(_ code: GCKeyCode) {
        let kb = GCKeyboard.coalesced?.keyboardInput
        let shift = (kb?.button(forKeyCode: .leftShift)?.isPressed ?? false)
                 || (kb?.button(forKeyCode: .rightShift)?.isPressed ?? false)

        if shift {
            switch code {
            case .one:   debugSpawnPowerUp(.shield)
            case .two:   debugSpawnPowerUp(.twinLaser)
            case .three: debugSpawnPowerUp(.boost)
            case .four:  debugSpawnPowerUp(.minelayer)
            case .five:  debugSpawnPowerUp(.torpedo)
            default: break
            }
        } else {
            switch code {
            case .one:   debugSpawnAsteroid()
            case .two:   debugSpawnUFO()
            case .three: debugSpawnMine()
            case .four:  debugSpawnRock()
            case .five:  debugSpawnAlien()
            case .six:   debugSpawnSnake()
            default: break
            }
        }
    }

    // MARK: - Spawners

    private func debugSpawnAsteroid() {
        let entry = randomEdgeEntry()
        let velocity = CGPoint.fromAngle(entry.inwardAngle, length: 110)
        spawn(Spawn(kind: .asteroid(radius: 28, seed: UInt64.random(in: 0..<UInt64.max)),
                    position: entry.position, velocity: velocity, side: entry.side))
    }

    private func debugSpawnUFO() {
        let entry = randomEdgeEntry()
        spawn(Spawn(kind: .ufo(baseHeading: entry.inwardAngle, seed: UInt64.random(in: 0..<UInt64.max)),
                    position: entry.position, velocity: .zero, side: entry.side))
    }

    private func debugSpawnMine() {
        let bounds = playBounds
        let margin: CGFloat = 80
        let position = CGPoint(
            x: CGFloat.random(in: bounds.minX + margin...bounds.maxX - margin),
            y: CGFloat.random(in: bounds.minY + margin...bounds.maxY - margin)
        )
        spawn(Spawn(kind: .mine, position: position, velocity: .zero, side: .top))
    }

    private func debugSpawnRock() {
        let entry = randomEdgeEntry()
        let velocity = CGPoint.fromAngle(entry.inwardAngle, length: 80)
        spawn(Spawn(kind: .rock(radius: 42, seed: UInt64.random(in: 0..<UInt64.max)),
                    position: entry.position, velocity: velocity, side: entry.side))
    }

    private func debugSpawnAlien() {
        let entry = randomEdgeEntry()
        spawn(Spawn(kind: .alienMonster(baseHeading: entry.inwardAngle,
                                        seed: UInt64.random(in: 0..<UInt64.max)),
                    position: entry.position, velocity: .zero, side: entry.side))
    }

    private func debugSpawnSnake() {
        let entry = randomEdgeEntry()
        spawn(Spawn(kind: .snake(baseHeading: entry.inwardAngle,
                                 seed: UInt64.random(in: 0..<UInt64.max)),
                    position: entry.position, velocity: .zero, side: entry.side))
    }

    private func debugSpawnPowerUp(_ kind: PowerUpKind) {
        let entry = randomEdgeEntry()
        let velocity = CGPoint.fromAngle(entry.inwardAngle, length: 70)
        spawn(Spawn(kind: .powerUp(kind: kind, speed: 70, lifetime: nil),
                    position: entry.position, velocity: velocity, side: entry.side))
    }

    // MARK: - Edge geometry

    private func randomEdgeEntry()
        -> (position: CGPoint, side: ScreenSide, inwardAngle: CGFloat)
    {
        let bounds = playBounds
        let side = ScreenSide.allCases.randomElement() ?? .top
        let inset: CGFloat = 8
        let position: CGPoint
        let inwardAngle: CGFloat
        switch side {
        case .top:
            position = CGPoint(x: CGFloat.random(in: bounds.minX + 40...bounds.maxX - 40),
                               y: bounds.maxY - inset)
            inwardAngle = -.pi / 2
        case .bottom:
            position = CGPoint(x: CGFloat.random(in: bounds.minX + 40...bounds.maxX - 40),
                               y: bounds.minY + inset)
            inwardAngle = .pi / 2
        case .left:
            position = CGPoint(x: bounds.minX + inset,
                               y: CGFloat.random(in: bounds.minY + 40...bounds.maxY - 40))
            inwardAngle = 0
        case .right:
            position = CGPoint(x: bounds.maxX - inset,
                               y: CGFloat.random(in: bounds.minY + 40...bounds.maxY - 40))
            inwardAngle = .pi
        }
        return (position, side, inwardAngle)
    }
}
#endif
