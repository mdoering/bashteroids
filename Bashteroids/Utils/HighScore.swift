import Foundation

enum HighScore {
    private static let key = "bashteroids.highScore"

    static var current: Int {
        UserDefaults.standard.integer(forKey: key)
    }

    @discardableResult
    static func recordIfHigher(_ score: Int) -> Bool {
        guard score > current else { return false }
        UserDefaults.standard.set(score, forKey: key)
        return true
    }
}
