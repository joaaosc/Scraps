import AppKit
import Observation
import OSLog
import StickyDomain
import StickyStorage

public enum StickyBoardError: Error, Equatable, LocalizedError, Sendable {
    case storeUnavailable
    public var errorDescription: String? {
        String(localized: "The folder where stickies are kept could not be reached, so none can be created.", bundle: .module)
    }
}

/// Owns one native window per sticky. Persistent and session notes share the
/// same editor while session content is routed exclusively to memory.
@MainActor
@Observable
public final class StickyBoard {
    public static let shared = StickyBoard()
    private static let logger = Logger(
        subsystem: StickyKitIdentity.bundleIdentifier, category: "Stickies"
    )

    public private(set) var activeStickyID: UUID?
    public private(set) var recentlyDeleted: [Sticky] = []
    public private(set) var lastError: String?
    public private(set) var openStickies: [Sticky] = []
    public private(set) var libraryStickies: [Sticky] = []
    public private(set) var globalShortcutEnabled = false
    @ObservationIgnored public var showSettingsHandler: (@MainActor () -> Void)?
    @ObservationIgnored public var showColorPickerHandler: (@MainActor () -> Void)?
    @ObservationIgnored private var store: (any StickyStore)?
    @ObservationIgnored private let sessionStore: MemoryStickyStore
    @ObservationIgnored private var sessionIDs: Set<UUID> = []
    @ObservationIgnored private var controllers: [UUID: StickyWindowController] = [:]
    @ObservationIgnored private var focusOnOpen: Set<UUID> = []
    @ObservationIgnored private var closedHere: Set<UUID> = []
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    @ObservationIgnored private var creations: [UUID: Task<Void, any Error>] = [:]
    @ObservationIgnored private var shortcut: StickyGlobalShortcut?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, sessionStore: MemoryStickyStore = MemoryStickyStore()) {
        self.defaults = defaults
        self.sessionStore = sessionStore
    }

    deinit {
        observation?.cancel()
        maintenance?.cancel()
    }

    public var activeModel: StickyModel? {
        guard let model = activeStickyID.flatMap({ controllers[$0]?.model }), !model.isClosing else { return nil }
        return model
    }
    public var hasOpenStickies: Bool { !openStickies.isEmpty }
    public var hasPendingStoreOperations: Bool { !creations.isEmpty }

    public func connect(to store: any StickyStore) {
        guard self.store == nil else { return }
        self.store = store
    }

    public func start() {
        guard observation == nil else { return }
        let changes = StickyChanges.stream()
        observation = Task { [weak self] in
            await self?.reconcile()
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.reconcile()
            }
        }
        maintenance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 * 60))
                guard !Task.isCancelled else { return }
                await self?.refreshRecentlyDeleted()
                if self == nil { return }
            }
        }
        if defaults.bool(forKey: "globalShortcutEnabled") {
            do { try setGlobalShortcutEnabled(true) }
            catch {
                defaults.set(false, forKey: "globalShortcutEnabled")
                report(String(localized: "Could not enable the global shortcut", bundle: .module), error)
            }
        }
    }

    public func addSticky(
        text: String = "", color: StickyColor? = nil, sessionOnly: Bool = false
    ) async throws {
        let target: any StickyStore
        if sessionOnly {
            target = sessionStore
        } else {
            guard let store else { throw StickyBoardError.storeUnavailable }
            target = store
        }
        let defaultColor = StickyColor(rawValue: defaults.string(forKey: "defaultStickyColor") ?? "clear") ?? .clear
        let floats = defaults.object(forKey: "defaultFloatsOnTop") == nil
            ? true : defaults.bool(forKey: "defaultFloatsOnTop")
        let sticky = Sticky(
            text: text,
            floatsOnTop: floats,
            color: color ?? defaultColor,
            appearsOnAllSpaces: defaults.bool(forKey: "defaultAppearsOnAllSpaces")
        )
        focusOnOpen.insert(sticky.id)
        if sessionOnly { sessionIDs.insert(sticky.id) }
        let creation = Task {
            try await target.save(sticky)
            // Creation also reconciles memory writes and stores whose change
            // announcements arrive later than the write itself.
            if observation != nil { await reconcile() }
        }
        creations[sticky.id] = creation
        defer { creations[sticky.id] = nil }
        do {
            try await creation.value
        } catch {
            focusOnOpen.remove(sticky.id)
            sessionIDs.remove(sticky.id)
            throw error
        }
    }

    public func newSticky(color: StickyColor? = nil, sessionOnly: Bool = false) {
        Task {
            do { try await addSticky(color: color, sessionOnly: sessionOnly) }
            catch { report(String(localized: "Could not create a sticky", bundle: .module), error) }
        }
    }

    public func newStickyInColor() { showColorPickerHandler?() }
    public func showSettings() { showSettingsHandler?() }
    public func toggleActiveFloating() { activeModel?.floatsOnTop.toggle() }
    public func toggleActiveCollapse() { activeModel?.toggleCollapsed() }
    public func toggleActiveAllSpaces() { activeModel?.appearsOnAllSpaces.toggle() }
    public func copyActiveText() { activeModel?.copyText() }
    public func sendActiveToNotes() { activeModel?.sendToNotes() }
    public func setActiveColor(_ color: StickyColor) { activeModel?.color = color }
    public func closeActive() { activeModel?.requestClose() }

    public func showSticky(_ id: UUID) {
        controllers[id]?.show(takingKeyboard: true)
    }

    public func openStoredSticky(_ id: UUID) async -> Bool {
        closedHere.remove(id)
        await reconcile()
        guard let controller = controllers[id] else { return false }
        controller.show(takingKeyboard: true)
        return true
    }

    public func isSessionOnly(_ id: UUID) -> Bool { sessionIDs.contains(id) }
    public func currentSnapshot(_ id: UUID) -> Sticky? {
        controllers[id]?.model.snapshot ?? libraryStickies.first { $0.id == id }
    }
    public func setPinned(_ pinned: Bool, id: UUID) {
        mutate(id: id) { $0.isPinned = pinned }
    }
    public func setTags(_ tags: [String], id: UUID) {
        mutate(id: id) { $0.tags = Sticky.normalizedTags(tags) }
    }
    public func setArchived(_ archived: Bool, id: UUID) {
        if !archived { closedHere.remove(id); focusOnOpen.insert(id) }
        mutate(id: id) { $0.isArchived = archived }
    }
    public func moveToTrash(_ id: UUID) {
        if let model = controllers[id]?.model { model.requestClose(); return }
        guard let note = currentSnapshot(id) else { return }
        let session = sessionIDs.contains(id)
        let task = Task { @MainActor in
            if session { await sessionStore.delete(id: id) }
            else if let recovery = store as? any RecentlyDeletedStickyStore {
                try await recovery.moveToTrash(note, at: Date())
            } else { throw StickyBoardError.storeUnavailable }
            await reconcile()
        }
        track(task, id: UUID())
    }

    public func duplicate(_ id: UUID) {
        guard let original = currentSnapshot(id) else { return }
        let copy = original.duplicated()
        let sessionOnly = sessionIDs.contains(id)
        persist(copy, sessionOnly: sessionOnly, focus: true)
    }
    private func mutate(id: UUID, change: @escaping @MainActor (inout Sticky) -> Void) {
        let task = Task { @MainActor in
            if let model = controllers[id]?.model {
                guard !model.isClosing else { return }
                var note = model.snapshot
                let wasArchived = note.isArchived
                change(&note)
                model.isPinned = note.isPinned
                model.isArchived = note.isArchived
                model.tags = note.tags
                await model.flush().value
                guard !model.hasUnsavedChanges else { model.isArchived = wasArchived; return }
            } else {
                guard var note = currentSnapshot(id) else { return }
                let previous = note
                change(&note)
                note.updatedAt = max(Date(), note.updatedAt, note.createdAt)
                let target: (any StickyStore)? = sessionIDs.contains(id) ? sessionStore : store
                guard let target else { throw StickyBoardError.storeUnavailable }
                if let files = target as? FileStickyStore { try await files.applySynchronized(note, replacing: previous) }
                else { try await target.save(note) }
            }
            await reconcile()
        }
        track(task, id: UUID())
    }
    private func persist(_ note: Sticky, sessionOnly: Bool, focus: Bool) {
        let task = Task { @MainActor in
            let target: (any StickyStore)? = sessionOnly ? sessionStore : store
            guard let target else { throw StickyBoardError.storeUnavailable }
            if sessionOnly { sessionIDs.insert(note.id) }
            if focus { focusOnOpen.insert(note.id) }
            try await target.save(note)
            await reconcile()
        }
        track(task, id: note.id)
    }
    public func recoverDraft(_ id: UUID) {
        guard let model = controllers[id]?.model else { return }
        let target: (any StickyStore)? = sessionIDs.contains(id) ? sessionStore : store
        guard let target else { return }
        model.recoverDraft { copy in try await target.save(copy) }
    }
    private func track(_ task: Task<Void, any Error>, id: UUID) {
        creations[id] = task
        Task {
            defer { creations[id] = nil }
            do { try await task.value }
            catch { report(String(localized: "Could not update this sticky", bundle: .module), error) }
        }
    }

    public func showAll() {
        NSApplication.shared.activate()
        let oldestFirst = controllers.values.sorted {
            $0.model.snapshot.createdAt < $1.model.snapshot.createdAt
        }
        for controller in oldestFirst.dropLast() { controller.show(takingKeyboard: false) }
        oldestFirst.last?.show(takingKeyboard: true)
    }

    public func closeAll() {
        let models = controllers.values.map(\.model)
        Task {
            for model in models { await model.requestClose().value }
            await refreshRecentlyDeleted()
        }
    }

    /// Share one readable collection through the focused window's native
    /// Notes service. The original notes remain open and unchanged.
    public func exportAllToNotes() {
        let ordered = controllers.values.sorted {
            $0.model.snapshot.createdAt < $1.model.snapshot.createdAt
        }
        let text = ordered.map(\.model.text)
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .joined(separator: "\n\n────────\n\n")
        guard !text.isEmpty, let controller = activeStickyID.flatMap({ controllers[$0] }) ?? ordered.last else { return }
        controller.shareCollection(text)
    }

    public func refreshRecentlyDeleted() async {
        guard let recoverable = store as? any RecentlyDeletedStickyStore else {
            recentlyDeleted = []
            return
        }
        do {
            try await recoverable.purgeExpired(now: Date())
            recentlyDeleted = try await recoverable.recentlyDeleted()
        } catch {
            lastError = String(format: String(localized: "Could not read Recently Deleted: %@", bundle: .module), error.localizedDescription)
            Self.logger.error("\(self.lastError ?? "", privacy: .public)")
        }
    }

    public func restoreSticky(_ id: UUID) {
        Task {
            guard let recoverable = store as? any RecentlyDeletedStickyStore else { return }
            focusOnOpen.insert(id)
            closedHere.remove(id)
            do {
                if try await recoverable.restore(id: id) == nil { focusOnOpen.remove(id) }
                await reconcile()
            } catch {
                focusOnOpen.remove(id)
                report(String(localized: "Could not restore this sticky", bundle: .module), error)
            }
        }
    }

    public func setGlobalShortcutEnabled(_ enabled: Bool) throws {
        guard enabled != globalShortcutEnabled else { return }
        if enabled {
            shortcut = try StickyGlobalShortcut { [weak self] in self?.newSticky() }
        } else {
            shortcut = nil
        }
        globalShortcutEnabled = enabled
        defaults.set(enabled, forKey: "globalShortcutEnabled")
    }

    private func reconcile() async {
        let session = await sessionStore.stickies()
        var stored = session
        var present = Set(session.map(\.id))
        if let store {
            do {
                let persistent = try await store.stickies()
                let persistentIDs = try await store.existingIdentifiers()
                stored += persistent
                present.formUnion(persistentIDs)
            } catch {
                // Disk availability must not prevent an in-memory capture.
                // Existing persistent editors stay open until absence is known.
                present.formUnion(controllers.keys.filter { !sessionIDs.contains($0) })
                lastError = String(format: String(localized: "Could not read the stickies: %@", bundle: .module), error.localizedDescription)
                Self.logger.error("\(self.lastError ?? "", privacy: .public)")
            }
        }
        stored.sort {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
        closedHere.formIntersection(present)
        libraryStickies = stored.map { controllers[$0.id]?.model.snapshot ?? $0 }
        present.subtract(stored.filter(\.isArchived).map(\.id))
        let visible = stored.filter { !$0.isArchived }
        let plan = StickyReconciliation(stored: visible.map(\.id), present: present, open: Array(controllers.keys))
        for id in plan.toClose {
            // An external change must never close an editor with an unsaved draft.
            guard let controller = controllers[id], !controller.model.isClosing else { continue }
            if controller.model.hasUnsavedChanges {
                // An archive written by this editor announces its change before
                // its save task drains. Its explicit operation reconciles again.
                if controller.model.isArchived { continue }
                recoverDraft(id)
            } else { controller.closeNow() }
        }
        for sticky in stored { controllers[sticky.id]?.model.applyStoredSnapshot(sticky) }
        for sticky in visible where plan.toOpen.contains(sticky.id) && !closedHere.contains(sticky.id) {
            guard controllers[sticky.id] == nil else { continue }
            if sessionIDs.contains(sticky.id) {
                open(sticky, store: sessionStore, sessionOnly: true)
            } else if let store {
                open(sticky, store: store, sessionOnly: false)
            }
        }
        updateOpenStickies()
        await refreshRecentlyDeleted()
    }

    private func open(_ sticky: Sticky, store: any StickyStore, sessionOnly: Bool) {
        let takesKeyboard = focusOnOpen.remove(sticky.id) != nil
        let controller = StickyWindowController(
            sticky: sticky, store: store, cascadeSlot: controllers.count,
            startsFocused: takesKeyboard, isSessionOnly: sessionOnly,
            onActivated: { [weak self] id in self?.stickyDidBecomeKey(id) },
            onDeactivated: { [weak self] id in self?.stickyDidResignKey(id) },
            onClosed: { [weak self] id in self?.windowClosed(id) }
        )
        controllers[sticky.id] = controller
        updateOpenStickies()
        controller.show(takingKeyboard: takesKeyboard)
    }

    func stickyDidBecomeKey(_ id: UUID) { activeStickyID = id }

    func stickyDidResignKey(_ id: UUID) {
        guard activeStickyID == id else { return }
        activeStickyID = nil
    }

    private func windowClosed(_ id: UUID) {
        controllers[id] = nil
        closedHere.insert(id)
        if activeStickyID == id { activeStickyID = nil }
        updateOpenStickies()
        Task { await refreshRecentlyDeleted() }
    }

    private func updateOpenStickies() {
        openStickies = controllers.values.map(\.model.snapshot).sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func flushAll() async -> Bool {
        var saved = true
        let pendingCreations = creations
        for (id, creation) in pendingCreations {
            do { try await creation.value }
            catch { saved = false }
            creations[id] = nil
        }
        // Keep these models alive even when a completed close removes its
        // controller during the awaits below.
        let models = controllers.values.map(\.model)
        let writes = models.map { $0.flush() }
        for write in writes { await write.value }
        return saved && creations.isEmpty && models.allSatisfy { !$0.hasUnsavedChanges }
    }

    /// A timed-out write continues with its models alive. The caller receives
    /// false so it can cancel quitting and keep the edits available.
    @discardableResult
    public func flushAll(within ceiling: Duration) async -> Bool {
        let gate = ResumeOnce()
        return await withCheckedContinuation { continuation in
            gate.continuation = continuation
            Task { gate.resume(await flushAll()) }
            Task { try? await Task.sleep(for: ceiling); gate.resume(false) }
        }
    }

    private func report(_ title: String, _ error: Error) {
        lastError = error.localizedDescription
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
private final class ResumeOnce {
    var continuation: CheckedContinuation<Bool, Never>?
    func resume(_ result: Bool) { continuation?.resume(returning: result); continuation = nil }
}
