import Foundation

/// Last 8 unique player names confirmed on title, most-recent first.
/// Persisted in UserDefaults so it survives app restarts.
enum RecentNames {
    private static let key = "recent_names"
    private static let limit = 8

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Record a confirmed name. Trims whitespace, dedupes (promoting the
    /// existing entry to the front), trims to `limit` entries.
    static func record(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = all
        current.removeAll { $0 == trimmed }
        current.insert(trimmed, at: 0)
        if current.count > limit { current = Array(current.prefix(limit)) }
        UserDefaults.standard.set(current, forKey: key)
    }
}
