import AppKit
import StickyDomain
import Observation

/// Observable editor state. Window effects and persistence are injected so edits,
/// recovery and the ordering of writes can be tested without a window server.
@MainActor
@Observable
public final class StickyModel {
    public enum Status: Equatable {
        case sentToNotes
        case shared
        case failure(String)
    }

    struct Dependencies {
        var save: @Sendable (Sticky) async throws -> Void
        var delete: @Sendable (UUID) async throws -> Void
        var share: @MainActor (
            String, CGRect, @escaping (NotesSharingAvailability.Outcome) -> Void
        ) -> Void
        var closeWindow: @MainActor () -> Void
        var applyLevel: @MainActor (Bool) -> Void
        var copyToPasteboard: @MainActor (String) -> Void
        /// Closing keeps the current snapshot, including an edit whose debounce
        /// has not elapsed. A session sticky deliberately bypasses recovery.
        var moveToTrash: (@Sendable (Sticky) async throws -> Void)? = nil
        var shareRichText: (@MainActor (
            String, StickyRichText?, CGRect,
            @escaping (NotesSharingAvailability.Outcome) -> Void
        ) -> Void)? = nil
        var copyRichText: (@MainActor (String, StickyRichText?) -> Void)? = nil
        var applyCollapsed: @MainActor (Bool) -> Void = { _ in }
        var applyAllSpaces: @MainActor (Bool) -> Void = { _ in }
        var applyColor: @MainActor (StickyColor) -> Void = { _ in }
        var updateTitle: @MainActor (String) -> Void = { _ in }
    }

    public var text: String {
        didSet { if text != oldValue { textDidChange() } }
    }
    public var richText: StickyRichText? {
        didSet {
            guard richText != oldValue else { return }
            base.edit(text: text, richText: richText)
            scheduleSave()
        }
    }
    public var color: StickyColor {
        didSet {
            guard color != oldValue else { return }
            base.color = color
            dependencies.applyColor(color)
            scheduleSave()
        }
    }
    public var floatsOnTop: Bool {
        didSet {
            guard floatsOnTop != oldValue else { return }
            base.floatsOnTop = floatsOnTop
            dependencies.applyLevel(floatsOnTop)
            scheduleSave()
        }
    }
    public var isCollapsed: Bool {
        didSet {
            guard isCollapsed != oldValue else { return }
            base.isCollapsed = isCollapsed
            dependencies.applyCollapsed(isCollapsed)
            scheduleSave()
        }
    }
    public var appearsOnAllSpaces: Bool {
        didSet {
            guard appearsOnAllSpaces != oldValue else { return }
            base.appearsOnAllSpaces = appearsOnAllSpaces
            dependencies.applyAllSpaces(appearsOnAllSpaces)
            scheduleSave()
        }
    }
    public private(set) var status: Status?
    public private(set) var isSharing = false
    public var isConfirmingDelete = false
    public let startsFocused: Bool
    public let isSessionOnly: Bool

    @ObservationIgnored public var sendButtonFrame: CGRect = .zero
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
        isSessionOnly: Bool = false,
        autosaveDelay: Duration = StickyAutosavePolicy.defaultDelay,
        autosaveCeiling: Duration = StickyAutosavePolicy.defaultCeiling,
        confirmationDuration: Duration = .seconds(3),
        sharingCeiling: Duration = .seconds(60),
        dependencies: Dependencies
    ) {
        base = sticky
        text = sticky.text
        richText = sticky.richText
        color = sticky.color
        floatsOnTop = sticky.floatsOnTop
        isCollapsed = sticky.isCollapsed
        appearsOnAllSpaces = sticky.appearsOnAllSpaces
        self.startsFocused = startsFocused
        self.isSessionOnly = isSessionOnly
        self.autosaveDelay = autosaveDelay
        self.autosaveCeiling = autosaveCeiling
        self.confirmationDuration = confirmationDuration
        self.sharingCeiling = sharingCeiling
        self.dependencies = dependencies
    }

    public var id: UUID { base.id }
    public var title: String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let line = firstLine.trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? String(localized: "Untitled", bundle: .module) : line
    }

    public var snapshot: Sticky {
        var sticky = base
        sticky.text = text
        sticky.richText = richText
        sticky.color = color
        sticky.floatsOnTop = floatsOnTop
        sticky.isCollapsed = isCollapsed
        sticky.appearsOnAllSpaces = appearsOnAllSpaces
        return sticky
    }

    public var sendUnavailableReason: String? {
        NotesSharingAvailability.unavailableReason(forText: text)
    }
    public var canSend: Bool { sendUnavailableReason == nil && !isSharing }

    public func sendToNotes() {
        guard canSend else { return }
        isSharing = true
        status = nil
        shareGeneration += 1
        let generation = shareGeneration
        startSharingTimeout(for: generation)
        let completion: (NotesSharingAvailability.Outcome) -> Void = { [weak self] outcome in
            guard let self, shareGeneration == generation, isSharing else { return }
            sharingDidEnd(outcome)
        }
        if let shareRichText = dependencies.shareRichText {
            shareRichText(text, richText, sendButtonFrame, completion)
        } else {
            dependencies.share(text, sendButtonFrame, completion)
        }
    }

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

    public func copyText() {
        if let copyRichText = dependencies.copyRichText {
            copyRichText(text, richText)
        } else {
            dependencies.copyToPasteboard(text)
        }
    }

    public func toggleCollapsed() { isCollapsed.toggle() }

    /// Closing is immediate and recoverable. Session notes are removed from
    /// memory; persistent notes go to Recently Deleted without a question.
    @discardableResult
    public func requestClose() -> Task<Void, Never> {
        Task { await deleteAndClose() }
    }

    @discardableResult
    func confirmDelete() -> Task<Void, Never> { requestClose() }

    func deleteAndClose() async {
        guard !isDeleted else { return }
        isDeleted = true
        autosaveTask?.cancel()
        await lastSave?.value
        do {
            if !isSessionOnly, let moveToTrash = dependencies.moveToTrash {
                try await moveToTrash(snapshot)
            } else {
                try await dependencies.delete(base.id)
            }
            dependencies.closeWindow()
        } catch {
            isDeleted = false
            // A failed close keeps the editor alive. Resume the save cancelled
            // for deletion so its pending text remains safe without another edit.
            if isDirty { scheduleSave() }
            show(.failure(String(format: String(localized: "Could not close this sticky: %@", bundle: .module), error.localizedDescription)), for: nil)
        }
    }

    func frameDidChange(_ frame: StickyFrame) {
        guard base.frame != frame else { return }
        base.frame = frame
        scheduleSave()
    }

    private func textDidChange() {
        base.edit(text: text)
        // A plain-text replacement cannot reuse ranges from the previous text.
        richText = nil
        dependencies.updateTitle(title)
        if status == .sentToNotes || status == .shared { status = nil }
        scheduleSave()
    }

    private func scheduleSave() {
        guard !isDeleted else { return }
        isDirty = true
        base.updatedAt = max(Date(), base.createdAt)
        let now = ContinuousClock.now
        let first = firstUnsavedChange ?? now
        firstUnsavedChange = first
        let wait = StickyAutosavePolicy.delay(
            debounce: autosaveDelay, ceiling: autosaveCeiling, sinceFirstChange: now - first
        )
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    @discardableResult
    public func flush() -> Task<Void, Never> {
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

    private func saveDidFail(_ error: Error) {
        isDirty = true
        firstUnsavedChange = firstUnsavedChange ?? .now
        hasSaveFailure = true
        show(.failure(String(format: String(localized: "Could not save this sticky: %@", bundle: .module), error.localizedDescription)), for: nil)
    }
}
