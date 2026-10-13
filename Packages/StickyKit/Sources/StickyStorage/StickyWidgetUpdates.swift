#if canImport(WidgetKit)
import Foundation
import StickyDomain
import WidgetKit

public actor StickyWidgetUpdates {
    public static let shared = StickyWidgetUpdates()
    private var observation: Task<Void, Never>?
    private var reload: Task<Void, Never>?
    private var previous: [Sticky] = []

    public func observe(_ store: FileStickyStore) {
        guard observation == nil else { return }
        let stream = StickyChanges.stream()
        observation = Task { [weak self] in
            await self?.update(store)
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await self?.update(store)
            }
        }
    }

    private func update(_ store: FileStickyStore) async {
        guard let notes = try? await store.stickies() else { return }
        let content = notes.filter { !$0.isArchived }.map {
            var snapshot = StickySyncMerge.cloudCopy($0)
            snapshot.updatedAt = .distantPast
            return snapshot
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard content != previous else { return }
        previous = content
        reload?.cancel()
        reload = Task {
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
#endif
