import Foundation

/// A made shot: where the file was and where it went.
struct Shot {
    let original: URL
    let trashed: URL
}

/// Moves scored files to the Trash and puts them back on undo.
final class TrashCan {
    struct Trashed {
        /// Finder did it, so Put Back works and Finder played its own trash sound.
        let byFinder: Bool
        /// Whether Hoop knows where the file went, so it can undo.
        let undoable: Bool
    }

    private(set) var history: [Shot] = []
    var lastShot: Shot? { history.last }

    /// Asks Finder first; if Finder can't (say, no permission to control it), moves the file itself.
    /// Calls back on the main queue.
    func trash(_ url: URL, completion: @escaping (Result<Trashed, Error>) -> Void) {
        Finder.trash(url) { [weak self] trashed in
            guard let self else { return }
            if let trashed {
                history.append(Shot(original: url, trashed: trashed))
                return completion(.success(Trashed(byFinder: true, undoable: true)))
            }
            // Finder may have trashed it but not said where.
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return completion(.success(Trashed(byFinder: true, undoable: false)))
            }
            do {
                var moved: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &moved)
                history.append(Shot(original: url, trashed: moved as URL? ?? url))
                completion(.success(Trashed(byFinder: false, undoable: true)))
            } catch {
                completion(.failure(error))
            }
        }
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
