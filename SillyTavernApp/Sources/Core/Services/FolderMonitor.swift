import Foundation

// MARK: - Folder Monitor (NSFilePresenter)

/// Monitors a directory and subdirectories for changes using NSFilePresenter.
/// Works on both macOS and iOS.
/// Includes debouncing to coalesce rapid file system events.
final class FolderMonitor: NSObject, NSFilePresenter {
    private let url: URL
    private let callback: @MainActor @Sendable () -> Void
    private var isRegistered = false
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration

    /// Default debounce interval for file system events
    static let defaultDebounceInterval: Duration = .milliseconds(200)

    // MARK: - NSFilePresenter

    var presentedItemURL: URL? { url }

    var presentedItemOperationQueue: OperationQueue {
        OperationQueue.main
    }

    // MARK: - Init

    init(url: URL, debounceInterval: Duration = FolderMonitor.defaultDebounceInterval, callback: @escaping @MainActor @Sendable () -> Void) {
        self.url = url
        self.debounceInterval = debounceInterval
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
        debounceTask?.cancel()
        debounceTask = nil
        NSFileCoordinator.removeFilePresenter(self)
        isRegistered = false
    }

    // MARK: - Debounced Callback

    /// Schedules the callback with debouncing to coalesce rapid events.
    /// Each call cancels any pending callback and starts a new delay.
    private func scheduleCallback() {
        debounceTask?.cancel()
        let cb = callback
        let delay = debounceInterval
        debounceTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await cb()
        }
    }

    // MARK: - File Changes

    /// Called when the presented directory itself changes
    func presentedItemDidChange() {
        scheduleCallback()
    }

    /// Called when a file or folder inside the directory changes
    func presentedSubitemDidChange(at url: URL) {
        scheduleCallback()
    }

    /// Called when a subitem is added
    func presentedSubitemDidAppear(at url: URL) {
        scheduleCallback()
    }

    /// Called when a subitem moves
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        scheduleCallback()
    }
}
