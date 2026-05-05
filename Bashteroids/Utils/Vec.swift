import CoreGraphics

extension CGPoint {
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func *(p: CGPoint, s: CGFloat) -> CGPoint {
        CGPoint(x: p.x * s, y: p.y * s)
    }

    static func *(s: CGFloat, p: CGPoint) -> CGPoint {
        p * s
    }

    static func /(p: CGPoint, s: CGFloat) -> CGPoint {
        CGPoint(x: p.x / s, y: p.y / s)
    }

    static func +=(lhs: inout CGPoint, rhs: CGPoint) {
        lhs = lhs + rhs
    }

    static func -=(lhs: inout CGPoint, rhs: CGPoint) {
        lhs = lhs - rhs
    }

    var lengthSquared: CGFloat {
        x * x + y * y
    }

    var length: CGFloat {
        sqrt(lengthSquared)
    }

    var angle: CGFloat {
        atan2(y, x)
    }

    func normalized() -> CGPoint {
        let len = length
        return len > 0 ? self / len : .zero
    }

    func clampedMagnitude(to maxLength: CGFloat) -> CGPoint {
        let len = length
        return len > maxLength ? self * (maxLength / len) : self
    }

    func distance(to other: CGPoint) -> CGFloat {
        (self - other).length
    }

    func distanceSquared(to other: CGPoint) -> CGFloat {
        (self - other).lengthSquared
    }

    static func fromAngle(_ radians: CGFloat, length: CGFloat = 1) -> CGPoint {
        CGPoint(x: cos(radians) * length, y: sin(radians) * length)
    }
}
