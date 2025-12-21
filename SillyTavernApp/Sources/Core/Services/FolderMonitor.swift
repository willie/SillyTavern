import Foundation

// MARK: - Folder Monitor (NSFilePresenter)

/// Monitors a directory and subdirectories for changes using NSFilePresenter.
/// Works on both macOS and iOS.
final class FolderMonitor: NSObject, NSFilePresenter {
    private let url: URL
    private let callback: () -> Void
    private var isRegistered = false

    // MARK: - NSFilePresenter

    var presentedItemURL: URL? { url }

    var presentedItemOperationQueue: OperationQueue {
        OperationQueue.main
    }

    // MARK: - Init

    init(url: URL, callback: @escaping () -> Void) {
        self.url = url
        self.callback = callback
        super.init()
    }

    deinit {
        stop()
    }

    // MARK: - Start/Stop

    func start() {
        guard !isRegistered else { return }
        NSFileCoordinator.addFilePresenter(self)
        isRegistered = true
    }

    func stop() {
        guard isRegistered else { return }
        NSFileCoordinator.removeFilePresenter(self)
        isRegistered = false
    }

    // MARK: - File Changes

    /// Called when the presented directory itself changes
    func presentedItemDidChange() {
        callback()
    }

    /// Called when a file or folder inside the directory changes
    func presentedSubitemDidChange(at url: URL) {
        callback()
    }

    /// Called when a subitem is added
    func presentedSubitemDidAppear(at url: URL) {
        callback()
    }

    /// Called when a subitem moves
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        callback()
    }
}
