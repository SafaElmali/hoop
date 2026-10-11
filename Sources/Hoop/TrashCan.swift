import Foundation

/// A made shot: where the file was and where it went.
struct Shot {
    let original: URL
    let trashed: URL
}

/// Moves scored files to the Trash and puts them back on undo.
final class TrashCan {
    private(set) var history: [Shot] = []
    var lastShot: Shot? { history.last }

    func trash(_ url: URL) throws {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        history.append(Shot(original: url, trashed: trashed as URL? ?? url))
    }

    /// Moves the last trashed file back to where it came from and returns its restored location.
    func undo() throws -> URL {
        guard let shot = history.last else { throw CocoaError(.fileNoSuchFile) }
        let restored = Self.freeURL(for: shot.original.lastPathComponent, in: shot.original.deletingLastPathComponent())
        try FileManager.default.moveItem(at: shot.trashed, to: restored)
        history.removeLast()
        return restored
    }

    /// `name`, or "name 2", "name 3"… if something with that name already exists in `folder`.
    private static func freeURL(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
