import Foundation
import StickyDomain
import Synchronization
import Testing
@testable import StickyStorage

@Suite("File sticky store")
struct FileStickyStoreTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(limit: Int = FileStickyStore.maximumCount) throws
        -> (store: FileStickyStore, directory: URL)
    {
        let directory = URL.temporaryDirectory
            .appending(path: "StickyKitTests")
            .appending(path: UUID().uuidString)
            .appending(path: "Stickies")
        let store = try FileStickyStore(
            directoryURL: directory,
            limit: limit,
            announcesChanges: false
        )
        return (store, directory)
    }

    private func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func files(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test("Each sticky is one file named after its identifier")
    func oneFilePerSticky() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        let first = Sticky(text: "Buy milk", createdAt: instant)
        let second = Sticky(text: "Call Ana", createdAt: instant.addingTimeInterval(1))

        try await store.save(first)
        try await store.save(second)

        #expect(try files(in: directory) == [
            "\(first.id.uuidString).json",
            "\(second.id.uuidString).json",
        ].sorted())
    }

    @Test("Stickies come back oldest first and survive a new store")
    func listsAndPersists() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        let older = Sticky(text: "Older", createdAt: instant)
        let newer = Sticky(
            text: "Newer",
            createdAt: instant.addingTimeInterval(5),
            frame: StickyFrame(x: 1, y: 2, width: 260, height: 200),
            floatsOnTop: false
        )
        try await store.save(newer)
        try await store.save(older)

        let reopened = try FileStickyStore(directoryURL: directory, announcesChanges: false)
        let stored = try await reopened.stickies()

        #expect(stored == [older, newer])
    }

    @Test("Deleting removes only that file, and twice is not an error")
    func deletes() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        let kept = Sticky(text: "Keep", createdAt: instant)
        let gone = Sticky(text: "Gone", createdAt: instant.addingTimeInterval(1))
        try await store.save(kept)
        try await store.save(gone)

        try await store.delete(id: gone.id)
        try await store.delete(id: gone.id)

        #expect(try await store.stickies() == [kept])
        #expect(try files(in: directory) == ["\(kept.id.uuidString).json"])
    }

    @Test("An edit keeps the creation time and moves the update time")
    func editKeepsCreation() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        var sticky = Sticky(text: "Buy milk", createdAt: instant)
        try await store.save(sticky)

        sticky.edit(text: "Buy oat milk", at: instant.addingTimeInterval(90))
        try await store.save(sticky)
        let stored = try #require(try await store.stickies().first)

        #expect(try await store.stickies().count == 1)
        #expect(stored.text == "Buy oat milk")
        #expect(stored.createdAt == instant)
        #expect(stored.updatedAt == instant.addingTimeInterval(90))
    }

    @Test("A file that cannot be decoded is skipped and stays on disk")
    func skipsUnreadableFiles() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        let sticky = Sticky(text: "Readable", createdAt: instant)
        try await store.save(sticky)
        let broken = directory.appending(path: "\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: broken)

        let stored = try await store.stickies()

        #expect(stored == [sticky])
        #expect(FileManager.default.fileExists(atPath: broken.path))
    }

    @Test("An unreadable file does not use up room under the cap")
    func unreadableFilesDoNotCount() async throws {
        let (store, directory) = try makeStore(limit: 1)
        defer { cleanUp(directory) }
        try Data("not json".utf8).write(
            to: directory.appending(path: "\(UUID().uuidString).json")
        )

        try await store.save(Sticky(text: "Fits", createdAt: instant))

        #expect(try await store.stickies().count == 1)
    }

    @Test("The hundred-and-first sticky is refused with a way out, and nothing is dropped")
    func capIsHard() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        for index in 0..<FileStickyStore.maximumCount {
            try await store.save(
                Sticky(text: "Sticky \(index)", createdAt: instant.addingTimeInterval(Double(index)))
            )
        }

        let error = await #expect(throws: FileStickyStoreError.self) {
            try await store.save(Sticky(text: "One too many", createdAt: instant))
        }

        #expect(error == .limitReached(100))
        #expect(error?.errorDescription?.contains("Close a sticky to make room") == true)
        #expect(try await store.stickies().count == FileStickyStore.maximumCount)
        #expect(!(try await store.stickies().contains { $0.text == "One too many" }))
    }

    @Test("Editing a sticky is allowed when the store is full")
    func editingIgnoresCap() async throws {
        let (store, directory) = try makeStore(limit: 2)
        defer { cleanUp(directory) }
        var first = Sticky(text: "First", createdAt: instant)
        try await store.save(first)
        try await store.save(Sticky(text: "Second", createdAt: instant.addingTimeInterval(1)))

        first.edit(text: "First, edited", at: instant.addingTimeInterval(2))
        try await store.save(first)

        #expect(try await store.stickies().first?.text == "First, edited")
    }

    @Test("Closing one makes room for another")
    func deletingMakesRoom() async throws {
        let (store, directory) = try makeStore(limit: 1)
        defer { cleanUp(directory) }
        let first = Sticky(text: "First", createdAt: instant)
        try await store.save(first)

        try await store.delete(id: first.id)
        try await store.save(Sticky(text: "Second", createdAt: instant))

        #expect(try await store.stickies().map(\.text) == ["Second"])
    }

    @Test("A file with an unsupported version is skipped and kept")
    func skipsUnsupportedVersion() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        let sticky = Sticky(text: "Readable", createdAt: instant)
        try await store.save(sticky)
        let futureID = UUID()
        let future = directory.appending(path: "\(futureID.uuidString).json")
        let json = """
        {"version": 99, "sticky": {"id": "\(futureID.uuidString)", "text": "From later",
        "createdAt": "2027-01-01T00:00:00Z", "updatedAt": "2027-01-01T00:00:00Z", "floatsOnTop": true}}
        """
        try Data(json.utf8).write(to: future)

        #expect(try await store.stickies() == [sticky])
        #expect(FileManager.default.fileExists(atPath: future.path))
        let identifiers = try await store.existingIdentifiers()
        #expect(identifiers == Set([sticky.id, futureID]))
    }

    @Test("An unreadable file still counts as existing")
    func unreadableFileExists() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        let id = UUID()
        try Data("not json".utf8).write(to: directory.appending(path: "\(id.uuidString).json"))
        try Data("ignored".utf8).write(to: directory.appending(path: "notes.txt"))
        try Data("ignored".utf8).write(to: directory.appending(path: "not-a-uuid.json"))

        #expect(try await store.stickies().isEmpty)
        let identifiers = try await store.existingIdentifiers()
        #expect(identifiers == Set([id]), "got \(identifiers) want \(id) files \((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])")
    }

    @Test("Two stores on one folder: one creates while the other edits another sticky")
    func twoStoresOneFolder() async throws {
        let (mineStore, directory) = try makeStore()
        defer { cleanUp(directory) }
        let other = try FileStickyStore(directoryURL: directory, announcesChanges: false)
        var mine = Sticky(text: "Mine", createdAt: instant)
        try await mineStore.save(mine)

        async let created: Void = other.save(
            Sticky(text: "From the other", createdAt: instant.addingTimeInterval(1))
        )
        mine.edit(text: "Mine, edited", at: instant.addingTimeInterval(2))
        try await mineStore.save(mine)
        try await created

        let stored = try await mineStore.stickies()
        #expect(stored.map(\.text) == ["Mine, edited", "From the other"])
        #expect(try await other.stickies() == stored)
    }

    @Test("A write signals this process directly, without the system notification")
    func signalsInProcess() async throws {
        let (store, directory) = try makeStore()
        defer { cleanUp(directory) }
        let received = Mutex(false)
        let stream = StickyChanges.stream()
        let listener = Task {
            for await _ in stream {
                received.withLock { $0 = true }
                break
            }
        }
        defer { listener.cancel() }

        try await store.save(Sticky(text: "Hello", createdAt: instant))

        let deadline = ContinuousClock.now + .seconds(20)
        while !received.withLock({ $0 }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(received.withLock { $0 })
    }

    @Test("The default folder lives in Application Support, under the app's identifier")
    func defaultDirectory() throws {
        let support = URL(filePath: "/tmp/container/Library/Application Support")
        let url = try FileStickyStore.defaultDirectoryURL(applicationSupportResolver: { support })

        #expect(
            url.path
                == "/tmp/container/Library/Application Support/\(StickyKitIdentity.bundleIdentifier)/Stickies"
        )
        #expect(throws: CocoaError.self) {
            try FileStickyStore.defaultDirectoryURL(
                applicationSupportResolver: { throw CocoaError(.fileNoSuchFile) }
            )
        }
    }
}
