import Foundation

/// Wakes the capture loop when Notification Center writes its database, using kernel file events
/// (kqueue via DispatchSource) instead of polling. SQLite in WAL mode appends to `db-wal` for
/// each new notification and recreates or truncates it on checkpoints, so the files are re-armed
/// whenever they are replaced and the folder is watched for them reappearing.
final class DatabaseChangeMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ct106.notiforward.database-monitor")
    private let folder: String
    private let files: [String]
    // All state below is only touched on `queue`.
    private var sources: [DispatchSourceFileSystemObject] = []
    private var hasPendingChange = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var waitGeneration = 0

    init(databasePath: String) {
        folder = (databasePath as NSString).deletingLastPathComponent
        files = [databasePath, databasePath + "-wal"]
        queue.sync { arm() }
    }

    deinit { stop() }

    /// Returns after the database changes, or after `timeout` as a safety net for missed events.
    /// A change that arrives while nobody is waiting is remembered, so the next call returns at once.
    func waitForChange(timeout: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if self.hasPendingChange {
                    self.hasPendingChange = false
                    continuation.resume()
                    return
                }
                self.waitGeneration += 1
                let generation = self.waitGeneration
                self.waiter = continuation
                self.queue.asyncAfter(deadline: .now() + .seconds(Int(timeout.components.seconds))) {
                    guard self.waitGeneration == generation else { return }
                    self.resumeWaiter()
                }
            }
        }
    }

    func stop() {
        queue.sync {
            sources.forEach { $0.cancel() }
            sources.removeAll()
            resumeWaiter()
        }
    }

    private func signalChange() {
        if waiter != nil {
            resumeWaiter()
        } else {
            hasPendingChange = true
        }
    }

    private func resumeWaiter() {
        waiter?.resume()
        waiter = nil
    }

    private func arm() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        // Folder writes mean an entry was added or removed, such as db-wal being recreated.
        watch(folder, events: .write, rearm: true)
        for file in files {
            watch(file, events: [.write, .extend, .delete, .rename, .revoke], rearm: false)
        }
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent, rearm alwaysRearm: Bool) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self, unowned source] in
            guard let self else { return }
            self.signalChange()
            if alwaysRearm || !source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                self.arm()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }
}
