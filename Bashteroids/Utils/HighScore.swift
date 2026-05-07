import Foundation

struct HighScoreEntry: Codable {
    let name: String
    let score: Int
    let level: Int?
}

enum HighScore {
    private static let key = "bashteroids.highScores"
    static let maxEntries = 10

    static var top: [HighScoreEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([HighScoreEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func record(name: String, score: Int, level: Int) {
        guard score > 0 else { return }
        var list = top
        list.append(HighScoreEntry(name: name, score: score, level: level))
        list.sort { $0.score > $1.score }
        if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
