import Foundation
import StickyDomain
import StickyStorage
import Testing
@testable import StickyMobileUI

@Suite("Mobile sticky library")
@MainActor
struct MobileStickyLibraryTests {
    @Test("Changing color preserves a future modification timestamp")
    func colorKeepsMonotonicTimestamp() async throws {
        let future = Date().addingTimeInterval(86_400)
        let sticky = Sticky(text: "A future thought", createdAt: future, updatedAt: future.addingTimeInterval(100), color: .yellow)
        let durable = MemoryStickyStore(stickies: [sticky])
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        await library.reload()

        library.setColor(.blue, id: sticky.id)
        await library.flush()

        #expect(library.sticky(id: sticky.id)?.updatedAt == sticky.updatedAt)
        #expect(await durable.stickies().first?.updatedAt == sticky.updatedAt)
    }

    @Test("A repeated recovery cannot replace a newer unsaved draft")
    func repeatedRecoveryKeepsDraft() async throws {
        let durable = MemoryStickyStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let sticky = try #require(await library.newSticky(text: "Original"))
        #expect(await library.moveToTrash(id: sticky.id))
        await library.restore(id: sticky.id)
        library.edit(id: sticky.id, text: "Edited after recovery", richText: nil)

        await library.restore(id: sticky.id)

        #expect(library.sticky(id: sticky.id)?.text == "Edited after recovery")
        await library.flush()
        #expect(await durable.stickies().first?.text == "Edited after recovery")
    }

    @Test("An outdated permanent-delete action cannot remove a recovered sticky")
    func outdatedDeleteKeepsRecoveredSticky() async throws {
        let durable = MemoryStickyStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let sticky = try #require(await library.newSticky(text: "Keep this thought"))
        #expect(await library.moveToTrash(id: sticky.id))
        await library.restore(id: sticky.id)

        await library.permanentlyDelete(id: sticky.id)

        #expect(await durable.stickies().first?.id == sticky.id)
        #expect(library.sticky(id: sticky.id) != nil)
    }

    @Test("Opening a sticky from an app action dismisses Recently Deleted without losing drafts")
    func appActionClosesTrash() async throws {
        let durable = MemoryStickyStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let original = try #require(await library.newSticky(text: "Original"))
        library.edit(id: original.id, text: "Still editing", richText: nil)
        library.presentation = .recentlyDeleted
        let created = try #require(await library.newSticky(text: "From Shortcuts"))

        library.openSticky(id: created.id)

        #expect(library.presentation == nil)
        #expect(library.navigation == [created.id])
        await library.flush()
        #expect(await durable.stickies().contains { $0.id == original.id && $0.text == "Still editing" })
    }

    @Test("Session editing never creates a durable note")
    func sessionStaysInMemory() async throws {
        let durable = MemoryStickyStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let sticky = try #require(await library.newSticky(text: "Temporary", sessionOnly: true))

        library.edit(id: sticky.id, text: "Temporary\nKeep nearby", richText: nil)
        await library.flush()
        await library.reload()

        #expect(library.isSessionOnly(id: sticky.id))
        #expect(library.sticky(id: sticky.id)?.text == "Temporary\nKeep nearby")
        #expect(await durable.stickies().isEmpty)

        #expect(await library.moveToTrash(id: sticky.id))
        await library.reload()
        await library.restore(id: sticky.id)
        #expect(library.isSessionOnly(id: sticky.id))
        #expect(await durable.stickies().isEmpty)
    }

    @Test("Background flush keeps formatting and a changed color")
    func flushKeepsRichDraft() async throws {
        let durable = MemoryStickyStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let sticky = try #require(await library.newSticky(text: "A thought"))
        let format = StickyRichText(runs: [StickyTextRun(location: 0, length: 1, bold: true)])

        library.edit(id: sticky.id, text: "A thought", richText: format)
        library.setColor(.purple, id: sticky.id)
        await library.flush()

        let stored = try #require(await durable.stickies().first)
        #expect(stored.richText == format)
        #expect(stored.color == .purple)
        #expect(library.saveStates[sticky.id] == .saved)
    }

    @Test("Failed saves retain the visible draft through refresh and retry")
    func failedSaveRetainsDraft() async throws {
        let durable = ControlledMobileStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let sticky = try #require(await library.newSticky(text: "Original"))
        await durable.rejectSaves(true)

        library.edit(id: sticky.id, text: "Unsaved thought", richText: nil)
        await library.flush()
        await library.reload()

        #expect(library.sticky(id: sticky.id)?.text == "Unsaved thought")
        #expect(library.saveStates[sticky.id] == .failed)
        #expect(library.notice != nil)
        await durable.rejectSaves(false)
        await library.retrySave(id: sticky.id)
        #expect(library.saveStates[sticky.id] == .saved)
        #expect(try await durable.stickies().first?.text == "Unsaved thought")
    }

    @Test("A refresh captured before a new sticky cannot remove it")
    func refreshKeepsConcurrentCreation() async throws {
        let durable = ControlledMobileStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        await library.reload()
        await durable.blockNextRead()
        let refresh = Task { await library.reload() }
        await durable.waitForCapturedRead()

        let sticky = try #require(await library.newSticky(text: "Created during refresh"))
        await durable.releaseRead()
        await refresh.value

        #expect(library.sticky(id: sticky.id)?.text == "Created during refresh")
    }

    @Test("A refresh captured before a successful save cannot revert the text")
    func refreshKeepsConcurrentSave() async throws {
        let durable = ControlledMobileStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let sticky = try #require(await library.newSticky(text: "Original"))
        await durable.blockNextRead()
        let refresh = Task { await library.reload() }
        await durable.waitForCapturedRead()

        library.edit(id: sticky.id, text: "New thought", richText: nil)
        await library.flush()
        await durable.releaseRead()
        await refresh.value

        #expect(library.sticky(id: sticky.id)?.text == "New thought")
        #expect(library.saveStates[sticky.id] == .saved)
    }

    @Test("Deleting preserves the last draft and prevents a late edit from restoring it")
    func deletionStopsLateSave() async throws {
        let durable = ControlledMobileStore()
        let library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        let sticky = try #require(await library.newSticky(text: "Original"))
        library.edit(id: sticky.id, text: "Last draft", richText: nil)
        await durable.blockNextTrash()
        let deletion = Task { await library.moveToTrash(id: sticky.id) }
        await durable.waitForTrash()

        library.edit(id: sticky.id, text: "Late editor event", richText: nil)
        #expect(library.sticky(id: sticky.id)?.text == "Last draft")
        await durable.releaseTrash()
        #expect(await deletion.value)
        await library.flush()

        #expect(try await durable.stickies().isEmpty)
        #expect(try await durable.recentlyDeleted().first?.text == "Last draft")
        await library.restore(id: sticky.id)
        #expect(library.sticky(id: sticky.id)?.text == "Last draft")
    }
}

private actor ControlledMobileStore: RecentlyDeletedStickyStore {
    private let memory = MemoryStickyStore()
    private var rejectsSaves = false
    private var shouldBlockRead = false
    private var readCaptured = false
    private var readGate: CheckedContinuation<Void, Never>?
    private var readWaiter: CheckedContinuation<Void, Never>?
    private var shouldBlockTrash = false
    private var trashEntered = false
    private var trashGate: CheckedContinuation<Void, Never>?
    private var trashWaiter: CheckedContinuation<Void, Never>?

    func rejectSaves(_ rejects: Bool) { rejectsSaves = rejects }

    func blockNextRead() { shouldBlockRead = true; readCaptured = false }

    func waitForCapturedRead() async {
        if readCaptured { return }
        await withCheckedContinuation { readWaiter = $0 }
    }

    func releaseRead() { readGate?.resume(); readGate = nil }

    func blockNextTrash() { shouldBlockTrash = true; trashEntered = false }

    func waitForTrash() async {
        if trashEntered { return }
        await withCheckedContinuation { trashWaiter = $0 }
    }

    func releaseTrash() { trashGate?.resume(); trashGate = nil }

    func stickies() async throws -> [Sticky] {
        let snapshot = await memory.stickies()
        if shouldBlockRead {
            shouldBlockRead = false
            readCaptured = true
            readWaiter?.resume()
            readWaiter = nil
            await withCheckedContinuation { readGate = $0 }
        }
        return snapshot
    }

    func existingIdentifiers() async throws -> Set<UUID> { await memory.existingIdentifiers() }

    func save(_ sticky: Sticky) async throws {
        if rejectsSaves { throw SaveFailure() }
        try await memory.save(sticky)
    }

    func delete(id: UUID) async throws { await memory.delete(id: id) }

    func recentlyDeleted() async throws -> [Sticky] { await memory.recentlyDeleted() }

    func moveToTrash(_ sticky: Sticky, at date: Date) async throws {
        if shouldBlockTrash {
            shouldBlockTrash = false
            trashEntered = true
            trashWaiter?.resume()
            trashWaiter = nil
            await withCheckedContinuation { trashGate = $0 }
        }
        await memory.moveToTrash(sticky, at: date)
    }

    func restore(id: UUID) async throws -> Sticky? { try await memory.restore(id: id) }

    func purgeExpired(now: Date) async throws { await memory.purgeExpired(now: now) }

    private struct SaveFailure: Error, LocalizedError {
        var errorDescription: String? { "The test store could not save this sticky." }
    }
}
