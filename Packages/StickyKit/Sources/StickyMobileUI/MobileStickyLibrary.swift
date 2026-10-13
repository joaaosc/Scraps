import Foundation
import Observation
import StickyDomain
import StickyStorage

public enum MobileStickySaveState: Equatable, Sendable {
    case saved
    case saving
    case failed
}

public enum MobileStickyPresentation: String, Identifiable, Sendable {
    case recentlyDeleted
    case settings
    case colorPicker

    public var id: Self { self }
}

public struct MobileStickyNotice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// The mobile app and every scene share one ordered write queue. A late
/// autosave can never undo a later edit, a deletion, or a recovery.
@Observable
@MainActor
public final class MobileStickyLibrary {
    public private(set) var stickies: [Sticky] = []
    public private(set) var recentlyDeleted: [Sticky] = []
    public private(set) var sessionIdentifiers: Set<UUID> = []
    public private(set) var saveStates: [UUID: MobileStickySaveState] = [:]
    public private(set) var hasLoaded = false
    public private(set) var deletingIdentifiers: Set<UUID> = []
    public var notice: MobileStickyNotice?
    public var navigation: [UUID] = []
    public var presentation: MobileStickyPresentation?

    @ObservationIgnored private let store: SessionStickyStore?
    @ObservationIgnored private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var writeQueue: Task<Void, Never>?
    @ObservationIgnored private var savedSnapshots: [UUID: Sticky] = [:]
    @ObservationIgnored private var revisions: [UUID: UInt64] = [:]
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var mutationVersion: UInt64 = 0

    public init(store: SessionStickyStore) {
        self.store = store
    }

    public init(error: any Error) {
        store = nil
        notice = MobileStickyNotice(message: error.localizedDescription)
        hasLoaded = true
    }

    public var isAvailable: Bool { store != nil }

    public func sticky(id: UUID) -> Sticky? {
        stickies.first { $0.id == id }
    }

    public func isSessionOnly(id: UUID) -> Bool {
        sessionIdentifiers.contains(id)
    }

    public func openSticky(id: UUID) {
        guard sticky(id: id) != nil else { return }
        presentation = nil
        navigation = [id]
    }

    public func showAll() {
        presentation = nil
        navigation = []
    }

    public func reload() async {
        guard let store, !isReloading else { return }
        isReloading = true
        defer { isReloading = false; hasLoaded = true }
        do {
            await writeQueue?.value
            let expectedVersion = mutationVersion
            // Housekeeping affects only expired tombstones; it never evicts
            // active stickies to make room for a new one.
            try await store.purgeExpired(now: Date())
            let loaded = try await store.stickies()
            let deleted = try await store.recentlyDeleted()
            // Preserve drafts whose save is pending or failed. A foreground
            // refresh must not replace the text still visible in the editor.
            var sessions: Set<UUID> = []
            for sticky in loaded + deleted {
                if await store.isSessionOnly(id: sticky.id) { sessions.insert(sticky.id) }
            }
            guard expectedVersion == mutationVersion else { return }
            let drafts = stickies.filter { saveStates[$0.id] != nil && saveStates[$0.id] != .saved }
            let draftIDs = Set(drafts.map(\.id))
            for note in loaded where !draftIDs.contains(note.id) { savedSnapshots[note.id] = note }
            stickies = loaded.filter { !draftIDs.contains($0.id) } + drafts
            recentlyDeleted = deleted.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
            sessionIdentifiers = sessions
            sortStickies()
        } catch {
            report(error)
        }
    }

    @discardableResult
    public func newSticky(text: String = "", sessionOnly: Bool = false, color selectedColor: StickyColor? = nil) async -> Sticky? {
        guard let store else { return nil }
        let defaults = UserDefaults.standard
        let color = selectedColor ?? StickyColor(rawValue: defaults.string(forKey: "defaultStickyColor") ?? "clear") ?? .clear
        let sticky = Sticky(text: text, color: color)
        let previous = writeQueue
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                if sessionOnly {
                    try await store.createSession(sticky)
                } else {
                    try await store.save(sticky)
                }
                self.stickies.append(sticky)
                self.mutationVersion &+= 1
                self.saveStates[sticky.id] = .saved
                self.savedSnapshots[sticky.id] = sticky
                if sessionOnly { self.sessionIdentifiers.insert(sticky.id) }
                self.sortStickies()
            } catch {
                self.report(error)
            }
        }
        writeQueue = operation
        await operation.value
        return self.sticky(id: sticky.id)
    }

    public func edit(id: UUID, text: String, richText: StickyRichText?) {
        guard !deletingIdentifiers.contains(id), let index = stickies.firstIndex(where: { $0.id == id }) else { return }
        var sticky = stickies[index]
        sticky.edit(text: text, richText: richText)
        guard sticky != stickies[index] else { return }
        stickies[index] = sticky
        mutationVersion &+= 1
        scheduleSave(id: id)
        sortStickies()
    }

    public func setColor(_ color: StickyColor, id: UUID) {
        guard !deletingIdentifiers.contains(id), let index = stickies.firstIndex(where: { $0.id == id }), stickies[index].color != color else { return }
        stickies[index].color = color
        stickies[index].updatedAt = max(Date(), stickies[index].updatedAt, stickies[index].createdAt)
        mutationVersion &+= 1
        scheduleSave(id: id)
        sortStickies()
    }

    public func setPinned(_ pinned: Bool, id: UUID) {
        updateMetadata(id: id) { $0.isPinned = pinned }
    }
    public func setArchived(_ archived: Bool, id: UUID) {
        updateMetadata(id: id) { $0.isArchived = archived }
    }
    public func setTags(_ tags: [String], id: UUID) {
        updateMetadata(id: id) { $0.tags = Sticky.normalizedTags(tags) }
    }
    public func duplicate(id: UUID) async -> Sticky? {
        guard let original = sticky(id: id), let store, !deletingIdentifiers.contains(id) else { return nil }
        let copy = original.duplicated()
        let session = isSessionOnly(id: id)
        let previous = writeQueue
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                if session { try await store.createSession(copy) }
                else { try await store.save(copy) }
                self.stickies.append(copy)
                self.mutationVersion &+= 1
                self.saveStates[copy.id] = .saved
                self.savedSnapshots[copy.id] = copy
                if session { self.sessionIdentifiers.insert(copy.id) }
                self.sortStickies()
            } catch { self.report(error) }
        }
        writeQueue = operation
        await operation.value
        return sticky(id: copy.id)
    }
    private func updateMetadata(id: UUID, update: (inout Sticky) -> Void) {
        guard !deletingIdentifiers.contains(id), let index = stickies.firstIndex(where: { $0.id == id }) else { return }
        var sticky = stickies[index]
        update(&sticky)
        guard sticky != stickies[index] else { return }
        sticky.updatedAt = max(Date(), sticky.updatedAt, sticky.createdAt)
        stickies[index] = sticky
        mutationVersion &+= 1
        scheduleSave(id: id)
        sortStickies()
    }

    public func retrySave(id: UUID) async {
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        await persist(id: id)
    }

    /// Called on navigation and backgrounding. Saves every draft immediately
    /// rather than waiting for the autosave debounce after suspension.
    public func flush() async {
        let identifiers = stickies.compactMap { saveStates[$0.id] == .saving || saveStates[$0.id] == .failed ? $0.id : nil }
        for id in identifiers {
            pendingSaves[id]?.cancel()
            pendingSaves[id] = nil
            await persist(id: id)
        }
        await writeQueue?.value
    }

    public func moveToTrash(id: UUID) async -> Bool {
        guard let store, !deletingIdentifiers.contains(id), let sticky = sticky(id: id) else { return false }
        deletingIdentifiers.insert(id)
        mutationVersion &+= 1
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        let previous = writeQueue
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer { self.deletingIdentifiers.remove(id) }
            do {
                try await store.moveToTrash(sticky, at: Date())
                self.stickies.removeAll { $0.id == id }
                self.mutationVersion &+= 1
                self.saveStates[id] = nil
                self.recentlyDeleted = try await store.recentlyDeleted()
            } catch {
                self.saveStates[id] = .failed
                self.report(error)
            }
        }
        writeQueue = operation
        await operation.value
        return self.sticky(id: id) == nil
    }

    public func restore(id: UUID) async {
        guard let store, sticky(id: id) == nil else { return }
        let previous = writeQueue
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.sticky(id: id) == nil else { return }
            do {
                if let sticky = try await store.restore(id: id) {
                    self.mutationVersion &+= 1
                    self.stickies.removeAll { $0.id == id }
                    self.stickies.append(sticky)
                    self.saveStates[id] = .saved
                    if await store.isSessionOnly(id: id) { self.sessionIdentifiers.insert(id) }
                    self.sortStickies()
                }
                self.recentlyDeleted = try await store.recentlyDeleted()
            } catch {
                self.report(error)
            }
        }
        writeQueue = operation
        await operation.value
    }

    public func permanentlyDelete(id: UUID) async {
        guard let store, sticky(id: id) == nil, recentlyDeleted.contains(where: { $0.id == id }) else { return }
        let previous = writeQueue
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.sticky(id: id) == nil,
                  self.recentlyDeleted.contains(where: { $0.id == id }) else { return }
            do {
                try await store.delete(id: id)
                self.recentlyDeleted.removeAll { $0.id == id }
                self.mutationVersion &+= 1
                self.sessionIdentifiers.remove(id)
            } catch {
                self.report(error)
            }
        }
        writeQueue = operation
        await operation.value
    }

    private func scheduleSave(id: UUID) {
        revisions[id, default: 0] &+= 1
        saveStates[id] = .saving
        pendingSaves[id]?.cancel()
        pendingSaves[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.persist(id: id)
        }
    }

    private func persist(id: UUID) async {
        guard let store, !deletingIdentifiers.contains(id), let snapshot = sticky(id: id) else { return }
        let revision = revisions[id, default: 0]
        let previous = writeQueue
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.sticky(id: id) != nil, !self.deletingIdentifiers.contains(id) else { return }
            do {
                try await store.save(snapshot, replacing: self.savedSnapshots[id])
                self.savedSnapshots[id] = snapshot
                if self.revisions[id, default: 0] == revision, self.sticky(id: id) != nil {
                    self.mutationVersion &+= 1
                    self.saveStates[id] = .saved
                }
            } catch {
                if let storageError = error as? FileStickyStoreError,
                   storageError == .newerEditExists(id) || storageError == .recentlyDeleted(id),
                   let draft = self.sticky(id: id) {
                    // A widget or another device won the original. Preserve the
                    // newest visible draft as a separate note before reloading.
                    self.deletingIdentifiers.insert(id)
                    defer { self.deletingIdentifiers.remove(id) }
                    var copy = draft.duplicated()
                    copy.conflictSourceID = id
                    do {
                        try await store.save(copy)
                        self.pendingSaves[id]?.cancel()
                        self.pendingSaves[id] = nil
                        self.stickies.removeAll { $0.id == id }
                        self.stickies.append(copy)
                        self.saveStates[id] = nil
                        self.saveStates[copy.id] = .saved
                        self.savedSnapshots[copy.id] = copy
                        self.navigation = self.navigation.map { $0 == id ? copy.id : $0 }
                        self.mutationVersion &+= 1
                        self.sortStickies()
                        return
                    } catch { self.report(error) }
                }
                if self.revisions[id, default: 0] == revision {
                    self.saveStates[id] = .failed
                }
                self.report(error)
            }
        }
        writeQueue = operation
        await operation.value
    }

    private func sortStickies() {
        stickies.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func report(_ error: any Error) {
        notice = MobileStickyNotice(message: error.localizedDescription)
    }
}
