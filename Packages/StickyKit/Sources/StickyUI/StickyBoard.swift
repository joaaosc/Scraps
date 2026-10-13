import AppKit
import OSLog
import StickyDomain
import StickyStorage

public enum StickyBoardError: Error, Equatable, LocalizedError, Sendable {
    case storeUnavailable

    public var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            "The folder where stickies are kept could not be reached, so none can be created."
        }
    }
}

/// Owns one window per sticky and keeps them equal to what the store holds.
///
/// Every write to the store is announced without saying what changed, so the
/// board reads the store again and reconciles: a new file opens a window and
/// brings it forward, a removed file closes its window. The board's own writes
/// arrive the same way, so every path that makes a sticky — the menu, an
/// intent, another process sharing the folder — ends in a window through one
/// door.
@MainActor
public final class StickyBoard {
    public static let shared = StickyBoard()

    private static let logger = Logger(
        subsystem: StickyKitIdentity.bundleIdentifier,
        category: "Stickies"
    )

    private var store: (any StickyStore)?
    private var controllers: [UUID: StickyWindowController] = [:]
    /// Stickies the person is creating or closing here, so the reading that
    /// reconciles does not treat the moment between the write and the window
    /// as a change to undo.
    private var focusOnOpen: Set<UUID> = []
    private var closedHere: Set<UUID> = []
    private var observation: Task<Void, Never>?

    init() {}

    /// Says where stickies are kept. From here on a sticky can be created;
    /// its window only appears once `start()` is called.
    ///
    /// Separate from `start()` because the two happen at different moments:
    /// the store is known as soon as the process begins, so an intent that
    /// launched the app never finds a board that cannot create, while windows
    /// wait for the app to finish launching. The first store given is kept.
    public func connect(to store: any StickyStore) {
        guard self.store == nil else { return }
        self.store = store
    }

    /// Begins keeping windows and store equal: opens every stored sticky, then
    /// follows changes. Calling it again does nothing.
    ///
    /// Without a store, as in tests and previews, nothing opens.
    public func start() {
        guard observation == nil, store != nil else { return }
        // The stream exists before the first reading, so a sticky created in
        // between is announced rather than missed.
        let changes = StickyChanges.stream()
        observation = Task { [weak self] in
            await self?.reconcile()
            for await _ in changes {
                await self?.reconcile()
            }
        }
    }

    /// Creates a sticky holding `text` and opens it with the keyboard in it.
    ///
    /// The window comes from the reconciliation the write sets off, not from
    /// here, so this returns once the sticky is stored.
    public func addSticky(text: String = "") async throws {
        guard let store else { throw StickyBoardError.storeUnavailable }
        let sticky = Sticky(text: text)
        focusOnOpen.insert(sticky.id)
        do {
            try await store.save(sticky)
        } catch {
            focusOnOpen.remove(sticky.id)
            throw error
        }
    }

    /// `addSticky()`, for a menu command: a failure is told in an alert.
    public func newSticky() {
        Task {
            do {
                try await addSticky()
            } catch {
                Self.alert("Could not create a sticky", error.localizedDescription)
            }
        }
    }

    /// Brings the app and every sticky in front of other apps' windows, oldest
    /// first, so the newest ends on top with the keyboard.
    public func showAll() {
        NSApplication.shared.activate()
        let oldestFirst = controllers.values.sorted {
            $0.model.snapshot.createdAt < $1.model.snapshot.createdAt
        }
        for controller in oldestFirst.dropLast() {
            controller.show(takingKeyboard: false)
        }
        oldestFirst.last?.show(takingKeyboard: true)
    }

    private func reconcile() async {
        guard let store else { return }
        let stored: [Sticky]
        let present: Set<UUID>
        do {
            stored = try await store.stickies()
            present = try await store.existingIdentifiers()
        } catch {
            Self.logger.error("Could not read the stickies: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Once the store agrees a sticky is gone, it no longer needs remembering.
        closedHere.formIntersection(present)

        let plan = StickyReconciliation(
            stored: stored.map(\.id),
            present: present,
            open: Array(controllers.keys)
        )
        for id in plan.toClose {
            controllers[id]?.closeNow()
        }
        for sticky in stored where plan.toOpen.contains(sticky.id) && !closedHere.contains(sticky.id) {
            open(sticky, store: store)
        }
    }

    /// Only a sticky made here takes the keyboard. One that comes back at
    /// launch, or arrives from another process, is shown in front without
    /// pulling focus from whatever the person is doing.
    private func open(_ sticky: Sticky, store: any StickyStore) {
        let takesKeyboard = focusOnOpen.remove(sticky.id) != nil
        let controller = StickyWindowController(
            sticky: sticky,
            store: store,
            cascadeSlot: controllers.count,
            startsFocused: takesKeyboard,
            onClosed: { [weak self] id in self?.windowClosed(id) }
        )
        controllers[sticky.id] = controller
        controller.show(takingKeyboard: takesKeyboard)
    }

    private func windowClosed(_ id: UUID) {
        controllers[id] = nil
        // A window that closed while its sticky is still stored was closed by
        // the person; keep it from being reopened by a reading that predates
        // the delete.
        closedHere.insert(id)
    }

    /// Writes every pending edit and returns when the writes have finished.
    public func flushAll() async {
        let writes = controllers.values.map { $0.model.flush() }
        for write in writes { await write.value }
    }

    /// `flushAll()`, but never for longer than `ceiling`: a quit waits for the
    /// text to be safe, not for a stuck disk.
    public func flushAll(within ceiling: Duration) async {
        let gate = ResumeOnce()
        await withCheckedContinuation { continuation in
            gate.continuation = continuation
            Task {
                await flushAll()
                gate.resume()
            }
            Task {
                try? await Task.sleep(for: ceiling)
                gate.resume()
            }
        }
    }

    /// Whether any sticky window is open, so a quit knows if it has anything
    /// to wait for.
    public var hasOpenStickies: Bool { !controllers.isEmpty }

    private static func alert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// Resumes a continuation the first time it is asked to, and never again.
@MainActor
private final class ResumeOnce {
    var continuation: CheckedContinuation<Void, Never>?

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
