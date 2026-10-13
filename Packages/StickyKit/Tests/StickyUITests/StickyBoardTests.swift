import CoreGraphics
import Foundation
import StickyDomain
import StickyStorage
import Testing
@testable import StickyUI

@Suite("Reconciling sticky windows")
struct StickyReconciliationTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test("A stored sticky with no window is opened, in storage order")
    func opensWhatIsMissing() {
        let plan = StickyReconciliation(stored: [a, b, c], open: [b])

        #expect(plan.toOpen == [a, c])
        #expect(plan.toClose.isEmpty)
    }

    @Test("A window whose sticky is gone is closed")
    func closesWhatIsGone() {
        let plan = StickyReconciliation(stored: [a], open: [a, b, c])

        #expect(plan.toOpen.isEmpty)
        #expect(plan.toClose == [b, c])
    }

    @Test("Nothing to do when windows and store agree")
    func steadyState() {
        #expect(StickyReconciliation(stored: [a, b], open: [b, a]).isEmpty)
        #expect(StickyReconciliation(stored: [], open: []).isEmpty)
    }

    @Test("A window whose sticky exists but cannot be read stays open")
    func unreadableIsNotGone() {
        let plan = StickyReconciliation(stored: [a], present: [a, b], open: [a, b])

        #expect(plan.isEmpty)
    }

    @Test("A window closes only when its file is really gone")
    func closesOnlyWhenGone() {
        let plan = StickyReconciliation(stored: [a], present: [a, b], open: [a, b, c])

        #expect(plan.toClose == [c])
    }

    @Test("A sticky read just before it was deleted does not open")
    func deletedBetweenReads() {
        let plan = StickyReconciliation(stored: [a, b], present: [a], open: [])

        #expect(plan.toOpen == [a])
    }

    @Test("Opening and closing can happen in one pass")
    func both() {
        let plan = StickyReconciliation(stored: [a, c], open: [b])

        #expect(plan.toOpen == [a, c])
        #expect(plan.toClose == [b])
    }
}

@Suite("When a sticky is saved")
struct StickyAutosavePolicyTests {
    private let debounce = Duration.milliseconds(400)
    private let ceiling = Duration.seconds(2)

    @Test("A fresh edit waits the whole pause")
    func freshEdit() {
        let wait = StickyAutosavePolicy.delay(debounce: debounce, ceiling: ceiling, sinceFirstChange: .zero)

        #expect(wait == debounce)
    }

    @Test("Typing that has gone on for a while waits only what the ceiling has left")
    func ceilingShortensTheWait() {
        let wait = StickyAutosavePolicy.delay(
            debounce: debounce,
            ceiling: ceiling,
            sinceFirstChange: .milliseconds(1_800)
        )

        #expect(wait == .milliseconds(200))
    }

    @Test("Past the ceiling the write is immediate")
    func pastTheCeiling() {
        let wait = StickyAutosavePolicy.delay(
            debounce: debounce,
            ceiling: ceiling,
            sinceFirstChange: .seconds(5)
        )

        #expect(wait == .zero)
    }
}

@MainActor
@Suite("Flushing the board when the app quits")
struct StickyBoardFlushTests {
    @Test("A board with no windows has nothing to wait for and finishes at once")
    func emptyBoard() async {
        let board = StickyBoard()

        await board.flushAll()
        await board.flushAll(within: .seconds(30))

        #expect(!board.hasOpenStickies)
    }
}

@MainActor
@Suite("Creating stickies on the board")
struct StickyBoardCreationTests {
    /// Keeps stickies in memory and announces nothing, so no window follows.
    private actor MemoryStickyStore: StickyStore {
        private var items: [Sticky] = []

        func stickies() -> [Sticky] { items }

        func save(_ sticky: Sticky) {
            items.removeAll { $0.id == sticky.id }
            items.append(sticky)
        }

        func delete(id: UUID) {
            items.removeAll { $0.id == id }
        }
    }

    private struct FullStickyStore: StickyStore {
        func stickies() -> [Sticky] { [] }
        func save(_ sticky: Sticky) throws { throw FileStickyStoreError.limitReached(1) }
        func delete(id: UUID) {}
    }

    @Test("A new sticky is stored with its text, and no window opens before the board starts")
    func storesTheText() async throws {
        let store = MemoryStickyStore()
        let board = StickyBoard()
        board.connect(to: store)

        try await board.addSticky(text: "Buy milk")
        try await board.addSticky()

        #expect(await store.stickies().map(\.text) == ["Buy milk", ""])
        #expect(!board.hasOpenStickies)
    }

    @Test("Without a store, creating says why instead of doing nothing")
    func explainsAMissingStore() async {
        let board = StickyBoard()

        await #expect(throws: StickyBoardError.storeUnavailable) {
            try await board.addSticky()
        }
        #expect(StickyBoardError.storeUnavailable.errorDescription?.isEmpty == false)
    }

    @Test("A store that refuses passes its reason on")
    func passesTheRefusalOn() async {
        let board = StickyBoard()
        board.connect(to: FullStickyStore())

        await #expect(throws: FileStickyStoreError.limitReached(1)) {
            try await board.addSticky(text: "One too many")
        }
    }
}

@Suite("Placing sticky windows")
struct StickyPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    @Test("A new sticky opens at the default size, and each one steps over the last")
    func cascades() {
        let first = StickyPlacement.frame(stored: nil, visibleFrames: [screen], cascadeSlot: 0)
        let second = StickyPlacement.frame(stored: nil, visibleFrames: [screen], cascadeSlot: 1)

        #expect(first.size == StickyPlacement.defaultSize)
        #expect(second.origin.x > first.origin.x)
        #expect(second.origin.y < first.origin.y)
        #expect(first.origin != second.origin)
    }

    @Test("The cascade comes back round instead of walking off the screen")
    func cascadeWraps() {
        let first = StickyPlacement.frame(stored: nil, visibleFrames: [screen], cascadeSlot: 0)
        let wrapped = StickyPlacement.frame(stored: nil, visibleFrames: [screen], cascadeSlot: 10)

        #expect(first == wrapped)
        #expect(screen.contains(wrapped))
    }

    @Test("A stored frame on a screen is used as it was left")
    func usesStoredFrame() {
        let stored = StickyFrame(x: 300, y: 400, width: 320, height: 240)

        let frame = StickyPlacement.frame(stored: stored, visibleFrames: [screen], cascadeSlot: 3)

        #expect(frame == CGRect(x: 300, y: 400, width: 320, height: 240))
    }

    @Test("A stored frame below the minimum is brought up to it")
    func enforcesMinimum() {
        let stored = StickyFrame(x: 300, y: 400, width: 10, height: 10)

        let frame = StickyPlacement.frame(stored: stored, visibleFrames: [screen], cascadeSlot: 0)

        #expect(frame.size == StickyPlacement.minimumSize)
    }

    @Test("A frame left on a screen that is gone comes back onto one, keeping its size")
    func rescuesOffscreenFrame() {
        let stored = StickyFrame(x: 5_000, y: 5_000, width: 320, height: 240)

        let frame = StickyPlacement.frame(stored: stored, visibleFrames: [screen], cascadeSlot: 0)

        #expect(screen.contains(frame))
        #expect(frame.size == CGSize(width: 320, height: 240))
    }
}

@Suite("Sending a sticky to Notes")
struct NotesSharingAvailabilityTests {
    @Test("Notes' own service is used when it exists and takes text")
    func usesNotesWhenPossible() {
        #expect(NotesSharingAvailability.route(serviceFound: true, canPerformWithText: true) == .notes)
    }

    @Test("Without the service, or when it refuses the text, the picker is offered")
    func fallsBackToThePicker() {
        #expect(NotesSharingAvailability.route(serviceFound: false, canPerformWithText: false) == .picker)
        #expect(NotesSharingAvailability.route(serviceFound: true, canPerformWithText: false) == .picker)
    }

    @Test("Blank text cannot be sent, and says why")
    func blankTextExplains() {
        #expect(NotesSharingAvailability.unavailableReason(forText: "  \n")?.isEmpty == false)
        #expect(NotesSharingAvailability.unavailableReason(forText: "Buy milk") == nil)
    }

    @Test("Closing Apple's sheet is a cancel, not a failure")
    func cancelIsNotAFailure() {
        let outcome = NotesSharingAvailability.outcome(
            for: CocoaError(.userCancelled),
            route: .notes
        )

        #expect(outcome == .cancelled)
    }

    @Test("Any other error is told in words, naming where it was going")
    func failureIsTold() {
        struct Refused: LocalizedError {
            var errorDescription: String? { "Notes is unavailable." }
        }

        let viaNotes = NotesSharingAvailability.outcome(for: Refused(), route: .notes)
        let viaPicker = NotesSharingAvailability.outcome(for: Refused(), route: .picker)

        #expect(viaNotes == .failed("Could not send this sticky to Notes: Notes is unavailable."))
        #expect(viaPicker == .failed("Could not share this sticky: Notes is unavailable."))
    }
}

/// Waits for a condition, giving up after a ceiling. Used instead of a fixed
/// sleep: it returns as soon as the work is done and tolerates a busy main
/// actor.
@MainActor
func eventually(
    timeout: Duration = .seconds(20),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

@MainActor
@Suite("A sticky's behaviour")
struct StickyModelTests {
    /// Records what the model asked of the outside world.
    @MainActor
    final class Spy {
        var saved: [Sticky] = []
        var deleted: [UUID] = []
        var events: [String] = []
        var shared: [String] = []
        var closedWindow = 0
        var level: Bool?
        var pasteboard: String?
        var shareCompletion: ((NotesSharingAvailability.Outcome) -> Void)?
        var shareCompletions: [(NotesSharingAvailability.Outcome) -> Void] = []
        var failSaves = false
        var blocksSaves = false
        var blockedSave: CheckedContinuation<Void, Never>?

        func save(_ sticky: Sticky) async throws {
            if blocksSaves {
                await withCheckedContinuation { blockedSave = $0 }
            }
            if failSaves { throw CocoaError(.fileWriteUnknown) }
            saved.append(sticky)
            events.append("save")
        }

        func delete(_ id: UUID) {
            deleted.append(id)
            events.append("delete")
        }

        func releaseSave() {
            blockedSave?.resume()
            blockedSave = nil
        }
    }

    private func makeModel(
        text: String,
        spy: Spy,
        autosave: Duration = .milliseconds(20),
        ceiling: Duration = .seconds(60),
        sharingCeiling: Duration = .seconds(60)
    ) -> StickyModel {
        let sticky = Sticky(text: text, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        return StickyModel(
            sticky: sticky,
            autosaveDelay: autosave,
            autosaveCeiling: ceiling,
            confirmationDuration: .milliseconds(30),
            sharingCeiling: sharingCeiling,
            dependencies: StickyModel.Dependencies(
                save: { sticky in try await spy.save(sticky) },
                delete: { id in await spy.delete(id) },
                share: { text, _, completion in
                    spy.shared.append(text)
                    spy.shareCompletion = completion
                    spy.shareCompletions.append(completion)
                },
                closeWindow: { spy.closedWindow += 1 },
                applyLevel: { spy.level = $0 },
                copyToPasteboard: { spy.pasteboard = $0 }
            )
        )
    }

    @Test("Edits are saved once, after they stop, with the creation time kept")
    func debouncedAutosave() async {
        let spy = Spy()
        let model = makeModel(text: "", spy: spy)
        let created = model.snapshot.createdAt

        model.text = "B"
        model.text = "Bu"
        model.text = "Buy milk"
        #expect(spy.saved.isEmpty)
        #expect(await eventually { !spy.saved.isEmpty })
        await model.flush().value

        #expect(spy.saved.map(\.text) == ["Buy milk"])
        #expect(spy.saved.first?.createdAt == created)
    }

    @Test("The ceiling writes even when the pause never comes")
    func ceilingForcesTheWrite() async {
        let spy = Spy()
        // A pause so long it would never end, and a ceiling that is short.
        let model = makeModel(text: "", spy: spy, autosave: .seconds(600), ceiling: .milliseconds(30))

        model.text = "Still typing"

        #expect(await eventually { !spy.saved.isEmpty })
        #expect(spy.saved.first?.text == "Still typing")
    }

    @Test("Flushing writes a pending edit at once")
    func flushWritesNow() async {
        let spy = Spy()
        let model = makeModel(text: "", spy: spy, autosave: .seconds(600))

        model.text = "Not yet saved"
        await model.flush().value

        #expect(spy.saved.map(\.text) == ["Not yet saved"])
    }

    @Test("Flushing with nothing pending writes nothing")
    func flushIsQuietWhenClean() async {
        let spy = Spy()
        let model = makeModel(text: "Saved", spy: spy)

        await model.flush().value

        #expect(spy.saved.isEmpty)
    }

    @Test("Where the window was left is saved with the same delay")
    func savesFrame() async {
        let spy = Spy()
        let model = makeModel(text: "Keep", spy: spy)

        model.frameDidChange(StickyFrame(x: 1, y: 2, width: 300, height: 220))

        #expect(await eventually { !spy.saved.isEmpty })
        #expect(spy.saved.last?.frame == StickyFrame(x: 1, y: 2, width: 300, height: 220))
        #expect(spy.saved.last?.text == "Keep")
    }

    @Test("Closing an empty sticky deletes it without asking")
    func emptyClosesSilently() async {
        let spy = Spy()
        let model = makeModel(text: " \n", spy: spy)

        await model.requestClose().value

        #expect(!model.isConfirmingDelete)
        #expect(spy.deleted == [model.id])
        #expect(spy.closedWindow == 1)
    }

    @Test("Closing a sticky with text asks first and deletes nothing yet")
    func textAsksFirst() async {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy)

        await model.requestClose().value

        #expect(model.isConfirmingDelete)
        #expect(spy.deleted.isEmpty)
        #expect(spy.closedWindow == 0)
    }

    @Test("Confirming the question deletes the sticky and closes the window")
    func confirmDeletes() async {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy)

        await model.confirmDelete().value

        #expect(spy.deleted == [model.id])
        #expect(spy.closedWindow == 1)
    }

    @Test("A save pending at delete time cannot bring the sticky back")
    func deleteWinsOverPendingSave() async {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy, autosave: .seconds(600))
        model.text = "Buy oat milk"

        await model.deleteAndClose()
        await model.flush().value

        #expect(spy.deleted == [model.id])
        #expect(spy.saved.isEmpty)
    }

    @Test("A save already in flight finishes before the delete, and nothing is saved after")
    func deleteWaitsForSaveInFlight() async {
        let spy = Spy()
        spy.blocksSaves = true
        let model = makeModel(text: "Buy milk", spy: spy, autosave: .seconds(600))
        model.text = "Buy oat milk"
        model.flush()
        #expect(await eventually { spy.blockedSave != nil })

        let deletion = model.confirmDelete()
        for _ in 0..<20 { await Task.yield() }
        #expect(spy.deleted.isEmpty)

        spy.blocksSaves = false
        spy.releaseSave()
        await deletion.value
        await model.flush().value

        #expect(spy.events == ["save", "delete"])
    }

    @Test("Blank text cannot be sent and the reason is available")
    func blankCannotSend() {
        let spy = Spy()
        let model = makeModel(text: "  ", spy: spy)

        model.sendToNotes()

        #expect(!model.canSend)
        #expect(model.sendUnavailableReason != nil)
        #expect(spy.shared.isEmpty)
    }

    @Test("A send to Notes confirms briefly and keeps the sticky open")
    func successConfirms() async {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy)

        model.sendToNotes()
        #expect(spy.shared == ["Buy milk"])
        spy.shareCompletion?(.sent(.notes))

        #expect(model.status == .sentToNotes)
        #expect(spy.closedWindow == 0)
        #expect(await eventually { model.status == nil })
    }

    @Test("Sending through the picker is never called Notes")
    func pickerIsNotNotes() {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy)

        model.sendToNotes()
        spy.shareCompletion?(.sent(.picker))

        #expect(model.status == .shared)
    }

    @Test("A cancelled send says nothing; a failed one says why and stays")
    func cancelAndFailure() {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy)

        model.sendToNotes()
        spy.shareCompletion?(.cancelled)
        #expect(model.status == nil)
        #expect(model.canSend)

        model.sendToNotes()
        spy.shareCompletion?(.failed("Could not send this sticky to Notes: no."))
        #expect(model.status == .failure("Could not send this sticky to Notes: no."))
    }

    @Test("A send that is never answered stops blocking the button after the ceiling")
    func unansweredSendIsGivenUp() async {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy, sharingCeiling: .milliseconds(30))

        model.sendToNotes()
        #expect(!model.canSend)

        #expect(await eventually { model.canSend })
        #expect(model.status == nil)
    }

    @Test("A late answer to a send already given up on is ignored")
    func lateAnswerIsIgnored() async {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy, sharingCeiling: .milliseconds(30))
        model.sendToNotes()
        #expect(await eventually { model.canSend })

        model.sendToNotes()
        spy.shareCompletions[0](.failed("old"))

        #expect(model.status == nil)
    }

    @Test("A failed save is shown in the sticky")
    func saveFailureShows() async {
        let spy = Spy()
        spy.failSaves = true
        let model = makeModel(text: "", spy: spy, autosave: .seconds(600))

        model.text = "Buy milk"
        await model.flush().value

        guard case let .failure(message)? = model.status else {
            Issue.record("Expected a failure status")
            return
        }
        #expect(message.hasPrefix("Could not save this sticky"))
    }

    @Test("A save that failed is tried again by the next flush, and the message goes")
    func failedSaveIsRetriedOnFlush() async {
        let spy = Spy()
        spy.failSaves = true
        let model = makeModel(text: "", spy: spy, autosave: .seconds(600))
        model.text = "Buy milk"
        await model.flush().value
        #expect(spy.saved.isEmpty)

        spy.failSaves = false
        await model.flush().value

        #expect(spy.saved.map(\.text) == ["Buy milk"])
        #expect(model.status == nil)
    }

    @Test("A later successful save clears the 'could not save' line")
    func laterSaveClearsTheMessage() async {
        let spy = Spy()
        spy.failSaves = true
        let model = makeModel(text: "", spy: spy, autosave: .seconds(600))
        model.text = "Buy"
        await model.flush().value
        #expect(model.status != nil)

        spy.failSaves = false
        model.text = "Buy milk"
        await model.flush().value

        #expect(model.status == nil)
        #expect(spy.saved.map(\.text) == ["Buy milk"])
    }

    @Test("Toggling Float on Top changes the window level and is saved")
    func floatToggle() async {
        let spy = Spy()
        let model = makeModel(text: "Keep", spy: spy, autosave: .seconds(600))

        model.floatsOnTop = false
        await model.flush().value

        #expect(spy.level == false)
        #expect(spy.saved.last?.floatsOnTop == false)
    }

    @Test("Copy Text puts the text on the pasteboard")
    func copies() {
        let spy = Spy()
        let model = makeModel(text: "Buy milk", spy: spy)

        model.copyText()

        #expect(spy.pasteboard == "Buy milk")
    }
}
