import Foundation

/// What the toast says about a shot.
struct Callout {
    let title: String
    /// Follows the file name in the toast, like "3 points".
    var note: String?
}

/// Keeps score: makes in a row this session, plus totals that last across launches.
final class Scorekeeper {
    private enum Rules {
        /// Makes in a row to catch fire.
        static let fireStreak = 3
        /// A make let go at least this far from the opening, in points, is a three.
        static let downtown: CGFloat = 700
        /// A trashed folder's size counts at most this many items.
        static let folderItems = 10_000
    }

    /// The totals, stored in UserDefaults under these names.
    private enum Key: String, CaseIterable {
        case makes, misses, bestStreak, bytesTrashed
    }

    private static let cheers = ["Swish!", "Buckets!", "Splash!", "Count it!", "Money"]

    private(set) var streak = 0
    var isOnFire: Bool { streak >= Rules.fireStreak }

    var makes: Int { self[.makes] }
    var misses: Int { self[.misses] }
    var bestStreak: Int { self[.bestStreak] }
    var bytesTrashed: Int { self[.bytesTrashed] }

    /// Disk space `url` takes up; a folder counts its first 10,000 items. Read it before the file moves.
    static func size(of url: URL) -> Int {
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        guard values.isDirectory == true else { return bytes(values) }
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        return items.prefix(Rules.folderItems).reduce(0) { total, item in
            guard let item = item as? URL, let values = try? item.resourceValues(forKeys: Set(keys)) else { return total }
            return total + bytes(values)
        }
    }

    /// Counts a make and picks its callout: a dunk, then a streak, then a bank shot, then a three,
    /// then a clean one. `bytes` is what it trashed (nothing, for a move into a folder).
    func recordMake(_ make: MakeInfo, bytes: Int) -> Callout {
        streak += 1
        self[.makes] += 1
        self[.bestStreak] = max(bestStreak, streak)
        self[.bytesTrashed] += bytes
        if make.isDunk { return Callout(title: "Dunk!") }
        if streak == Rules.fireStreak { return Callout(title: "On fire 🔥", note: "\(streak) in a row") }
        if isOnFire { return Callout(title: "\(streak) in a row 🔥") }
        if make.isBank { return Callout(title: "Bank shot!") }
        if make.distance >= Rules.downtown { return Callout(title: "From downtown!", note: "3 points") }
        if make.isClean { return Callout(title: "Nothing but net") }
        return Callout(title: Self.cheers.randomElement()!)
    }

    /// Counts a miss and ends the streak; there's only something to say when that puts out a fire.
    func recordMiss() -> Callout? {
        let wasOnFire = isOnFire
        streak = 0
        self[.misses] += 1
        return wasOnFire ? Callout(title: "Fire’s out") : nil
    }

    func reset() {
        streak = 0
        Key.allCases.forEach { UserDefaults.standard.removeObject(forKey: $0.rawValue) }
    }

    private subscript(key: Key) -> Int {
        get { UserDefaults.standard.integer(forKey: key.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: key.rawValue) }
    }

    private static func bytes(_ values: URLResourceValues) -> Int {
        values.totalFileAllocatedSize ?? values.fileSize ?? 0
    }
}
