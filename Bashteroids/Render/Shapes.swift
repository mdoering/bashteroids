import SpriteKit

enum ScreenSide: CaseIterable {
    case top, bottom, left, right
}

enum Shapes {

    // Ship: closed triangle pointing along +X (zRotation = 0 means facing right).
    // Stroked, no fill, color set per player.
    static func shipV(color: SKColor, scale: CGFloat = 1) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 14, y: 0))
        path.addLine(to: CGPoint(x: -10, y: 8))
        path.addLine(to: CGPoint(x: -6, y: 0))
        path.addLine(to: CGPoint(x: -10, y: -8))
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = 1.5
        node.lineJoin = .miter
        node.isAntialiased = true
        node.setScale(scale)
        return node
    }

    // Asteroid: irregular closed polygon. Same `seed` produces the same shape,
    // so each asteroid keeps its silhouette frame to frame.
    static func asteroid(radius: CGFloat, seed: UInt64, vertexCount: Int = 10) -> SKShapeNode {
        var rng = SeededGenerator(seed: seed)
        let count = max(8, min(12, vertexCount))
        let path = CGMutablePath()

        for i in 0..<count {
            let baseAngle = CGFloat(i) / CGFloat(count) * .pi * 2
            let angleJitter = rng.cgFloat(in: -0.15...0.15)
            let radiusJitter = rng.cgFloat(in: 0.7...1.15)
            let r = radius * radiusJitter
            let a = baseAngle + angleJitter
            let p = CGPoint.fromAngle(a, length: r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.strokeColor = .white
        node.fillColor = .clear
        node.lineWidth = 1.5
        node.isAntialiased = true

        let inner = SKShapeNode(circleOfRadius: radius * 0.38)
        inner.strokeColor = SKColor(white: 0.35, alpha: 1)
        inner.fillColor = .clear
        inner.lineWidth = 1
        inner.isAntialiased = true
        node.addChild(inner)

        return node
    }

    // UFO: classic flying-saucer silhouette in line segments.
    static func ufo(scale: CGFloat = 1) -> SKShapeNode {
        let path = CGMutablePath()

        // Lower hull (downward dome)
        path.move(to: CGPoint(x: -16, y: 0))
        path.addLine(to: CGPoint(x: -8, y: -6))
        path.addLine(to: CGPoint(x: 8, y: -6))
        path.addLine(to: CGPoint(x: 16, y: 0))

        // Mid plate
        path.addLine(to: CGPoint(x: -16, y: 0))

        // Upper dome
        path.move(to: CGPoint(x: -10, y: 0))
        path.addLine(to: CGPoint(x: -6, y: 6))
        path.addLine(to: CGPoint(x: 6, y: 6))
        path.addLine(to: CGPoint(x: 10, y: 0))

        let node = SKShapeNode(path: path)
        node.strokeColor = .white
        node.fillColor = .clear
        node.lineWidth = 1.5
        node.isAntialiased = true
        node.setScale(scale)
        return node
    }

    // Bullet: short laser line oriented along the heading.
    static func bullet(color: SKColor = .white, heading: CGFloat = 0) -> SKShapeNode {
        let half: CGFloat = 3
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -cos(heading) * half, y: -sin(heading) * half))
        path.addLine(to: CGPoint(x:  cos(heading) * half, y:  sin(heading) * half))
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = 1.5
        node.lineCap = .round
        node.isAntialiased = true
        return node
    }

    static func powerUp(kind: PowerUpKind) -> SKShapeNode {
        switch kind {
        case .shield:    return shieldPowerUp()
        case .dualCanon: return dualCanonPowerUp()
        }
    }

    private static func shieldPowerUp() -> SKShapeNode {
        let path = CGMutablePath()
        let r: CGFloat = 14
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * .pi * 2
            let p = CGPoint(x: r * cos(a), y: r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.strokeColor = SKColor(red: 0, green: 1, blue: 1, alpha: 1)
        node.fillColor = .clear
        node.lineWidth = 1.5
        node.isAntialiased = true
        return node
    }

    private static func dualCanonPowerUp() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -8, y:  2)); path.addLine(to: CGPoint(x: 8, y:  2))
        path.move(to: CGPoint(x: -8, y: -2)); path.addLine(to: CGPoint(x: 8, y: -2))
        let node = SKShapeNode(path: path)
        node.strokeColor = .yellow
        node.fillColor = .clear
        node.lineWidth = 1.5
        node.isAntialiased = true
        return node
    }

    static func mine() -> SKShapeNode {
        let r: CGFloat       = Mine.collisionRadius
        let spikeLen: CGFloat = 6
        let path = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * .pi * 2
            path.move(to:    CGPoint(x:  r             * cos(a), y:  r             * sin(a)))
            path.addLine(to: CGPoint(x: (r + spikeLen) * cos(a), y: (r + spikeLen) * sin(a)))
        }
        let container = SKShapeNode(path: path)
        container.strokeColor = .white
        container.fillColor   = .clear
        container.lineWidth   = 1.5
        container.isAntialiased = true

        let circle = SKShapeNode(circleOfRadius: r)
        circle.strokeColor = .white
        circle.fillColor   = .clear
        circle.lineWidth   = 1.5
        circle.isAntialiased = true
        container.addChild(circle)
        return container
    }

    // Edge glow: a rectangular bar laid along one screen side. Returned at
    // alpha 0; caller fades it in over the warning duration. Position is
    // anchored so the bar sits along the named edge of a frame `bounds`.
    static func edgeGlow(side: ScreenSide,
                         bounds: CGRect,
                         thickness: CGFloat = 24,
                         color: SKColor = .white) -> SKShapeNode {
        let rect: CGRect
        switch side {
        case .top:
            rect = CGRect(x: bounds.minX,
                          y: bounds.maxY - thickness,
                          width: bounds.width,
                          height: thickness)
        case .bottom:
            rect = CGRect(x: bounds.minX,
                          y: bounds.minY,
                          width: bounds.width,
                          height: thickness)
        case .left:
            rect = CGRect(x: bounds.minX,
                          y: bounds.minY,
                          width: thickness,
                          height: bounds.height)
        case .right:
            rect = CGRect(x: bounds.maxX - thickness,
                          y: bounds.minY,
                          width: thickness,
                          height: bounds.height)
        }

        let node = SKShapeNode(rect: rect)
        node.strokeColor = .clear
        node.fillColor = color
        node.alpha = 0
        node.blendMode = .add
        node.isAntialiased = false
        return node
    }
}
