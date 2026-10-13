import Foundation
import Observation
import StickyDomain
import StickyStorage

@MainActor
@Observable
public final class StickyCloudSync {
    public static let shared = StickyCloudSync()
    public private(set) var isEnabled: Bool
    public private(set) var status: StickySyncStatus = .disabled
    public private(set) var lastSyncedAt: Date?
    @ObservationIgnored private var service: StickySyncService?
    @ObservationIgnored private var transition: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "cloudSyncEnabled")
    }

    public func connect(to store: FileStickyStore, beforeImport: @escaping @Sendable () async -> Bool) {
        guard service == nil else { return }
        service = StickySyncService(store: store, beforeImport: beforeImport) { [weak self] status in
            await self?.receive(status)
        }
    }

    public func start() {
        guard isEnabled else { return }
        setEnabled(true)
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "cloudSyncEnabled")
        let acceptAccountChange = enabled && status == .accountChanged
        transition?.cancel()
        transition = Task {
            guard let service, !Task.isCancelled else { return }
            if enabled {
                status = .syncing
                await service.start(acceptAccountChange: acceptAccountChange)
            } else {
                await service.stop()
                guard !Task.isCancelled, !isEnabled else { return }
                status = .disabled
            }
        }
    }

    public func synchronize() async {
        await transition?.value
        guard isEnabled, let service else { return }
        await service.synchronize()
    }

    /// Background delivery must finish before the system's notification deadline.
    /// A slow operation remains owned by the engine and can resume later.
    public func synchronize(within ceiling: Duration) async -> Bool {
        let completion = StickySyncCompletion()
        return await withCheckedContinuation { continuation in
            completion.continuation = continuation
            Task {
                await synchronize()
                completion.resume(status == .upToDate)
            }
            Task {
                try? await Task.sleep(for: ceiling)
                completion.resume(false)
            }
        }
    }

    public var statusMessage: String {
        switch status {
        case .disabled: String(localized: "On this device only", bundle: .module)
        case .syncing: String(localized: "Syncing with iCloud…", bundle: .module)
        case .upToDate: String(localized: "Up to date in iCloud", bundle: .module)
        case .notSignedIn: String(localized: "Sign in to iCloud in System Settings to sync your notes.", bundle: .module)
        case .accountChanged: String(localized: "iCloud account changed. Your local notes are kept; enable sync to use this account.", bundle: .module)
        case let .failed(message): message
        }
    }

    private func receive(_ status: StickySyncStatus) {
        self.status = status
        if status == .upToDate { lastSyncedAt = Date() }
        if status == .accountChanged {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: "cloudSyncEnabled")
        }
    }
}

@MainActor
private final class StickySyncCompletion {
    var continuation: CheckedContinuation<Bool, Never>?
    func resume(_ value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
