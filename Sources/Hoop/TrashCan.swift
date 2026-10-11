import Foundation

/// A made shot: where the file was, where it is now and what it went into.
struct Shot {
    let original: URL
    let moved: URL
    let target: Target
}

/// Moves made files where they go, into the Trash or the folder hoop's folder, and puts them back on undo.
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
                history.append(Shot(original: url, moved: trashed, target: .trash))
                return completion(.success(Trashed(byFinder: true, undoable: true)))
            }
            // Finder may have trashed it but not said where.
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return completion(.success(Trashed(byFinder: true, undoable: false)))
            }
            do {
                var moved: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &moved)
                history.append(Shot(original: url, moved: moved as URL? ?? url, target: .trash))
                completion(.success(Trashed(byFinder: false, undoable: true)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Moves a file into `folder`, numbering its name if that's taken there. A file that's already
    /// in `folder` stays put, so there's nothing to undo. Returns whether it moved.
    func move(_ url: URL, into folder: URL) throws -> Bool {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath().path != folder.resolvingSymlinksInPath().path else { return false }
        let moved = Self.freeURL(for: url.lastPathComponent, in: folder)
        try FileManager.default.moveItem(at: url, to: moved)
        history.append(Shot(original: url, moved: moved, target: .folder(folder)))
        return true
    }

    /// Moves the last made file back to where it came from. Returns where it is now, and what it had gone into.
    func undo() throws -> (restored: URL, from: Target) {
        guard let shot = history.last else { throw CocoaError(.fileNoSuchFile) }
        let restored = Self.freeURL(for: shot.original.lastPathComponent, in: shot.original.deletingLastPathComponent())
        try FileManager.default.moveItem(at: shot.moved, to: restored)
        history.removeLast()
        return (restored, shot.target)
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
