import Foundation
import StickyDomain
import StickyStorage
import Testing

@Suite("Session sticky store")
struct SessionStickyStoreTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeFileStore(limit: Int = FileStickyStore.maximumCount) throws -> FileStickyStore {
        try FileStickyStore(
            directoryURL: URL.temporaryDirectory.appending(path: "ScrapsSessionTests-\(UUID().uuidString)"),
            limit: limit, announcesChanges: false
        )
    }

    @Test("Session notes, their edits and their trash never create a file")
    func sessionNeverTouchesDisk() async throws {
        let durable = try makeFileStore()
        defer { try? FileManager.default.removeItem(at: durable.directoryURL) }
        let store = SessionStickyStore(durable: durable)
        var sticky = Sticky(text: "Session idea", createdAt: instant, color: .green)
        try await store.createSession(sticky)
        sticky.edit(text: "Session idea 😀", at: instant.addingTimeInterval(1))
        try await store.save(sticky)
        try await store.moveToTrash(sticky, at: instant.addingTimeInterval(2))

        #expect(try await store.stickies().isEmpty)
        #expect(await store.isSessionOnly(id: sticky.id))
        #expect(try await store.recentlyDeleted().first?.text == sticky.text)
        #expect(try await store.restore(id: sticky.id) == sticky)
        #expect(try await durable.stickies().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: durable.directoryURL.path).isEmpty)

        let newSession = SessionStickyStore(durable: durable)
        #expect(try await newSession.stickies().isEmpty)
        #expect(try await newSession.recentlyDeleted().isEmpty)
    }

    @Test("Session routing survives deletion and expiry, including a delayed save")
    func lateSessionSaveStaysInMemory() async throws {
        let durable = try makeFileStore()
        defer { try? FileManager.default.removeItem(at: durable.directoryURL) }
        let store = SessionStickyStore(durable: durable)
        let sticky = Sticky(text: "Only RAM", createdAt: instant)
        try await store.createSession(sticky)
        try await store.delete(id: sticky.id)
        try await store.save(sticky)
        try await store.moveToTrash(sticky, at: instant)
        try await store.purgeExpired(now: instant.addingTimeInterval(FileStickyStore.trashRetentionInterval))
        try await store.save(sticky)

        #expect(await store.isSessionOnly(id: sticky.id))
        #expect(try await durable.existingIdentifiers().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: durable.directoryURL.path).isEmpty)
    }

    @Test("Mixed reads include durable and session notes, while relaunch retains only durable notes")
    func mixesBothStores() async throws {
        let durable = try makeFileStore()
        defer { try? FileManager.default.removeItem(at: durable.directoryURL) }
        let store = SessionStickyStore(durable: durable)
        let older = Sticky(text: "Durable", createdAt: instant)
        let newer = Sticky(text: "Session", createdAt: instant.addingTimeInterval(1))
        try await store.save(older)
        try await store.createSession(newer)

        #expect(try await store.stickies() == [older, newer])
        #expect(try await store.existingIdentifiers() == Set([older.id, newer.id]))
        #expect(!(await store.isSessionOnly(id: older.id)))
        #expect(await store.isSessionOnly(id: newer.id))
        #expect(try await SessionStickyStore(durable: durable).stickies() == [older])
    }

    @Test("Making a session durable keeps its RAM copy if the durable store is full")
    func conversionPreservesDataOnFailure() async throws {
        let durable = try makeFileStore(limit: 1)
        defer { try? FileManager.default.removeItem(at: durable.directoryURL) }
        let store = SessionStickyStore(durable: durable)
        let saved = Sticky(text: "Saved", createdAt: instant)
        let temporary = Sticky(text: "Temporary", createdAt: instant.addingTimeInterval(1))
        try await store.save(saved)
        try await store.createSession(temporary)

        let error = await #expect(throws: FileStickyStoreError.self) {
            try await store.makeDurable(id: temporary.id)
        }
        #expect(error == .limitReached(1))
        #expect(await store.isSessionOnly(id: temporary.id))
        #expect(try await store.stickies() == [saved, temporary])

        try await store.delete(id: saved.id)
        try await store.makeDurable(id: temporary.id)
        #expect(!(await store.isSessionOnly(id: temporary.id)))
        #expect(try await durable.stickies() == [temporary])
        #expect(try await store.stickies() == [temporary])
    }

    @Test("Memory trash restoration respects the active cap and keeps recovery data")
    func memoryRestoreCap() async throws {
        let store = MemoryStickyStore(limit: 1)
        let recoverable = Sticky(text: "Recoverable", createdAt: instant)
        let active = Sticky(text: "Active", createdAt: instant.addingTimeInterval(1))
        try await store.save(recoverable)
        await store.moveToTrash(recoverable, at: instant)
        try await store.save(active)

        let error = await #expect(throws: FileStickyStoreError.self) {
            try await store.restore(id: recoverable.id)
        }
        #expect(error == .limitReached(1))
        #expect(await store.recentlyDeleted().first?.text == "Recoverable")
        #expect(await store.stickies() == [active])
        await store.delete(id: active.id)
        #expect(try await store.restore(id: recoverable.id) == recoverable)
    }
}
