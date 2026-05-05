import SpriteKit

enum Explosion {
    static func burst(at position: CGPoint,
                      radius: CGFloat,
                      color: SKColor = .white,
                      parent: SKNode) {
        let shardCount = max(8, min(16, Int(radius * 0.6) + 6))
        let baseSpeed = max(70, radius * 4)

        for _ in 0..<shardCount {
            let length = CGFloat.random(in: 3...max(6, radius * 0.45))
            let shard = makeShard(length: length, color: color)
            shard.position = position
            parent.addChild(shard)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: baseSpeed * 0.5...baseSpeed)
            let lifetime = TimeInterval.random(in: 0.45...0.75)
            let dx = cos(angle) * speed * CGFloat(lifetime)
            let dy = sin(angle) * speed * CGFloat(lifetime)
            let spin = CGFloat.random(in: -6...6)

            shard.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: lifetime),
                    .rotate(byAngle: spin, duration: lifetime),
                    .fadeOut(withDuration: lifetime)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private static func makeShard(length: CGFloat, color: SKColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -length / 2, y: 0))
        path.addLine(to: CGPoint(x: length / 2, y: 0))

        let n = SKShapeNode(path: path)
        n.strokeColor = color
        n.lineWidth = 1.5
        n.lineCap = .round
        n.zRotation = CGFloat.random(in: 0...(2 * .pi))
        n.isAntialiased = true
        return n
    }
}
