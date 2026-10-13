import Foundation
import Testing
@testable import StickyDomain

@Suite("Cross-device note merges")
struct StickySyncMergeTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A remote edit replaces an unchanged note while preserving local window state")
    func remoteEdit() {
        let base = Sticky(text: "Original", createdAt: instant)
        var local = base
        local.frame = StickyFrame(x: 20, y: 40, width: 300, height: 220)
        local.isCollapsed = true
        local.floatsOnTop = false
        var remote = base
        remote.edit(text: "From iPhone", at: instant.addingTimeInterval(1))
        let merged = StickySyncMerge.resolve(local: local, remote: remote, ancestor: base)
        #expect(merged.note.text == "From iPhone")
        #expect(merged.note.frame == local.frame)
        #expect(merged.note.isCollapsed)
        #expect(!merged.note.floatsOnTop)
        #expect(merged.recoveredEdit == nil)
    }

    @Test("Independent edits of text, color and pinning combine without conflict copies")
    func independentEdits() {
        let base = Sticky(text: "Original", createdAt: instant, color: .yellow)
        var local = base
        local.edit(text: "Edited on Mac", at: instant.addingTimeInterval(1))
        var remote = base
        remote.color = .pink
        remote.isPinned = true
        remote.updatedAt = instant.addingTimeInterval(2)
        let merged = StickySyncMerge.resolve(local: local, remote: remote, ancestor: base)
        #expect(merged.note.text == "Edited on Mac")
        #expect(merged.note.color == .pink)
        #expect(merged.note.isPinned)
        #expect(merged.recoveredEdit == nil)
    }

    @Test("Concurrent Unicode text edits retain both versions and their formatting")
    func concurrentText() {
        let base = Sticky(text: "Original", createdAt: instant)
        var local = base
        local.edit(text: "café 👩🏽‍💻", richText: .init(runs: [.init(location: 0, length: 4, bold: true)]), at: instant.addingTimeInterval(1))
        var remote = base
        remote.edit(text: "日本語 — مرحبا", at: instant.addingTimeInterval(2))
        let id = UUID()
        let merged = StickySyncMerge.resolve(local: local, remote: remote, ancestor: base, conflictID: id)
        #expect(merged.note.text == remote.text)
        #expect(merged.recoveredEdit?.text == local.text)
        #expect(merged.recoveredEdit?.richText == local.richText)
        #expect(merged.recoveredEdit?.id == id)
        #expect(merged.recoveredEdit?.conflictSourceID == base.id)
        #expect(merged.recoveredEdit?.deletedAt == nil)
    }

    @Test("An edit concurrent with deletion remains available as an active recovered note")
    func editAndDelete() {
        let base = Sticky(text: "Original", createdAt: instant)
        var local = base
        local.deletedAt = instant.addingTimeInterval(3)
        var remote = base
        remote.edit(text: "Keep this new thought", at: instant.addingTimeInterval(2))
        let merged = StickySyncMerge.resolve(local: local, remote: remote, ancestor: base)
        #expect(merged.note.deletedAt != nil)
        #expect(merged.recoveredEdit?.text == remote.text)
        #expect(merged.recoveredEdit?.deletedAt == nil)
    }

    @Test("An explicit recovery on another device restores the original identifier")
    func remoteRecovery() {
        let base = Sticky(text: "Recover me", createdAt: instant, deletedAt: instant.addingTimeInterval(1))
        var restored = base
        restored.deletedAt = nil
        let merged = StickySyncMerge.resolve(local: base, remote: restored, ancestor: base)
        #expect(merged.note.deletedAt == nil)
        #expect(merged.note.id == base.id)
        #expect(merged.recoveredEdit == nil)
    }

    @Test("Window changes alone do not enqueue a cloud text mutation")
    func geometryIsLocal() {
        let base = Sticky(text: "Original", createdAt: instant)
        var moved = base
        moved.frame = StickyFrame(x: 200, y: 300, width: 400, height: 300)
        moved.updatedAt = instant.addingTimeInterval(2)
        moved.isCollapsed = true
        moved.appearsOnAllSpaces = true
        #expect(StickySyncMerge.equivalent(base, moved))
    }

    @Test("Tags normalize Unicode duplicates and duplication creates a fresh active note")
    func organizingNotes() throws {
        let note = Sticky(text: "Olá", createdAt: instant, color: .green, isCollapsed: true,
                          deletedAt: instant, isPinned: true, isArchived: true,
                          tags: [" #Café ", "cafe", "日本語", "", "work"])
        #expect(note.tags == ["Café", "日本語", "work"])
        let copy = note.duplicated(at: instant.addingTimeInterval(2))
        #expect(copy.id != note.id)
        #expect(copy.text == note.text)
        #expect(copy.tags == note.tags)
        #expect(copy.isPinned)
        #expect(!copy.isArchived)
        #expect(copy.deletedAt == nil)
        #expect(!copy.isCollapsed)
        #expect(try JSONDecoder().decode(Sticky.self, from: JSONEncoder().encode(note)) == note)
    }
}
