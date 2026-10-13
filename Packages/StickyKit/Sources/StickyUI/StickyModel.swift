import AppKit
import StickyDomain
import Observation

/// The state and actions of one sticky.
///
/// Owns the autosave: edits and moves are written a moment after they stop, and
/// `flush()` writes anything pending when the window closes or the app quits.
/// Everything that touches a window, the store or Notes is handed in, so the
/// rules here — when to ask before closing, when a save may still happen — can
/// be tested without any of them.
@MainActor
@Observable
final class StickyModel {
    enum Status: Equatable {
        case sentToNotes
        case shared
        case failure(String)
    }

    /// What the model needs from outside.
    struct Dependencies {
        var save: @Sendable (Sticky) async throws -> Void
        var delete: @Sendable (UUID) async throws -> Void
        /// Puts the text on its way to Notes. The anchor is the sending
        /// button's frame in window content coordinates.
        var share: @MainActor (
            _ text: String,
            _ anchor: CGRect,
            _ completion: @escaping (NotesSharingAvailability.Outcome) -> Void
        ) -> Void
        var closeWindow: @MainActor () -> Void
        var applyLevel: @MainActor (_ floatsOnTop: Bool) -> Void
        var copyToPasteboard: @MainActor (String) -> Void
    }

    var text: String {
        didSet { if text != oldValue { textDidChange() } }
    }
    var floatsOnTop: Bool {
        didSet { if floatsOnTop != oldValue { floatingDidChange() } }
    }
    private(set) var status: Status?
    var isConfirmingDelete = false
    private(set) var isSharing = false
    /// Whether the text field should take the keyboard when the window opens.
    let startsFocused: Bool

    @ObservationIgnored var sendButtonFrame: CGRect = .zero

    @ObservationIgnored private var base: Sticky
    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private let autosaveCeiling: Duration
    @ObservationIgnored private var firstUnsavedChange: ContinuousClock.Instant?
    @ObservationIgnored private var hasSaveFailure = false
    @ObservationIgnored private let confirmationDuration: Duration
    @ObservationIgnored private let sharingCeiling: Duration
    @ObservationIgnored private var shareGeneration = 0
    @ObservationIgnored private var sharingTimeout: Task<Void, Never>?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var lastSave: Task<Void, Never>?
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var isDeleted = false

    init(
        sticky: Sticky,
        startsFocused: Bool = false,
        autosaveDelay: Duration = StickyAutosavePolicy.defaultDelay,
        autosaveCeiling: Duration = StickyAutosavePolicy.defaultCeiling,
        confirmationDuration: Duration = .seconds(3),
        sharingCeiling: Duration = .seconds(60),
        dependencies: Dependencies
    ) {
        self.base = sticky
        self.text = sticky.text
        self.floatsOnTop = sticky.floatsOnTop
        self.startsFocused = startsFocused
        self.autosaveDelay = autosaveDelay
        self.autosaveCeiling = autosaveCeiling
        self.confirmationDuration = confirmationDuration
        self.sharingCeiling = sharingCeiling
        self.dependencies = dependencies
    }

    var id: UUID { base.id }

    /// What would be written right now.
    var snapshot: Sticky {
        var sticky = base
        sticky.floatsOnTop = floatsOnTop
        return sticky
    }

    // MARK: Sending

    /// Why the person cannot send this sticky yet, in words.
    var sendUnavailableReason: String? {
        NotesSharingAvailability.unavailableReason(forText: text)
    }

    var canSend: Bool { sendUnavailableReason == nil && !isSharing }

    func sendToNotes() {
        guard canSend else { return }
        isSharing = true
        status = nil
        shareGeneration += 1
        let generation = shareGeneration
        startSharingTimeout(for: generation)
        dependencies.share(text, sendButtonFrame) { [weak self] outcome in
            // An answer to a send that was already given up on is not about
            // the one in progress.
            guard let self, shareGeneration == generation else { return }
            sharingDidEnd(outcome)
        }
    }

    /// A service chosen from the picker may never report back. After the
    /// ceiling the button works again, claiming neither success nor failure.
    private func startSharingTimeout(for generation: Int) {
        sharingTimeout?.cancel()
        sharingTimeout = Task { [weak self, sharingCeiling] in
            try? await Task.sleep(for: sharingCeiling)
            guard !Task.isCancelled, let self, shareGeneration == generation else { return }
            isSharing = false
        }
    }

    private func sharingDidEnd(_ outcome: NotesSharingAvailability.Outcome) {
        sharingTimeout?.cancel()
        isSharing = false
        switch outcome {
        case .sent(.notes): show(.sentToNotes, for: confirmationDuration)
        case .sent(.picker): show(.shared, for: confirmationDuration)
        case .cancelled: status = nil
        case let .failed(message): show(.failure(message), for: nil)
        }
    }

    private func show(_ newStatus: Status, for duration: Duration?) {
        statusTask?.cancel()
        status = newStatus
        guard let duration else { return }
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.status = nil
        }
    }

    func copyText() {
        dependencies.copyToPasteboard(text)
    }

    // MARK: Closing

    /// Closing a sticky deletes it. An empty one goes silently; one with text
    /// asks first, because the text is kept nowhere else.
    ///
    /// - Returns: the deletion, for callers that need to wait for it. Already
    ///   finished when the question is being asked instead.
    @discardableResult
    func requestClose() -> Task<Void, Never> {
        if text.allSatisfy(\.isWhitespace) {
            return Task { await deleteAndClose() }
        }
        isConfirmingDelete = true
        return Task {}
    }

    @discardableResult
    func confirmDelete() -> Task<Void, Never> {
        Task { await deleteAndClose() }
    }

    func deleteAndClose() async {
        guard !isDeleted else { return }
        isDeleted = true
        autosaveTask?.cancel()
        // A save still in flight lands first, so it cannot recreate the file
        // after the delete.
        await lastSave?.value
        do {
            try await dependencies.delete(base.id)
            dependencies.closeWindow()
        } catch {
            isDeleted = false
            show(.failure("Could not delete this sticky: \(error.localizedDescription)"), for: nil)
        }
    }

    // MARK: Autosave

    /// Records where the window was left. Saved with the same delay as text.
    func frameDidChange(_ frame: StickyFrame) {
        guard base.frame != frame else { return }
        base.frame = frame
        scheduleSave()
    }

    private func textDidChange() {
        base.edit(text: text)
        // A confirmation is about the text that was sent, not the text now.
        if status == .sentToNotes || status == .shared { status = nil }
        scheduleSave()
    }

    private func floatingDidChange() {
        base.floatsOnTop = floatsOnTop
        dependencies.applyLevel(floatsOnTop)
        scheduleSave()
    }

    private func scheduleSave() {
        isDirty = true
        let now = ContinuousClock.now
        let first = firstUnsavedChange ?? now
        firstUnsavedChange = first
        // The wait restarts with each edit, but never runs past the ceiling
        // counted from the first change nobody has saved: continuous typing
        // must not postpone the write for ever.
        let wait = StickyAutosavePolicy.delay(
            debounce: autosaveDelay,
            ceiling: autosaveCeiling,
            sinceFirstChange: now - first
        )
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    /// Writes anything pending now. The returned task finishes when the write
    /// has; callers that must not lose text — closing, quitting — await it.
    @discardableResult
    func flush() -> Task<Void, Never> {
        autosaveTask?.cancel()
        if isDirty { commit() }
        return lastSave ?? Task {}
    }

    private func commit() {
        guard isDirty, !isDeleted else { return }
        isDirty = false
        firstUnsavedChange = nil
        let sticky = snapshot
        let previous = lastSave
        let save = dependencies.save
        lastSave = Task { [weak self] in
            // One write at a time, in order: the last edit must be the last
            // thing on disk.
            await previous?.value
            guard let self, !isDeleted else { return }
            do {
                try await save(sticky)
                saveDidSucceed()
            } catch {
                saveDidFail(error)
            }
        }
    }

    private func saveDidSucceed() {
        guard hasSaveFailure else { return }
        hasSaveFailure = false
        if case .failure = status { status = nil }
    }

    /// The text is still unsaved, so the next edit and the flush at close or
    /// quit try again.
    private func saveDidFail(_ error: Error) {
        isDirty = true
        firstUnsavedChange = firstUnsavedChange ?? .now
        hasSaveFailure = true
        show(
            .failure("Could not save this sticky: \(error.localizedDescription)"),
            for: nil
        )
    }
}
