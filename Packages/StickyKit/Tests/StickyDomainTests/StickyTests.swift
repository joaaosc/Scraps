import Foundation
import StickyDomain
import Testing

@Suite("Stickies")
struct StickyTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A sticky round-trips through JSON, placed or not")
    func roundTrips() throws {
        let placed = Sticky(
            text: "Call Ana ☾",
            createdAt: instant,
            frame: StickyFrame(x: 10, y: 20, width: 260, height: 200),
            floatsOnTop: false
        )
        let unplaced = Sticky(text: "Buy milk", createdAt: instant)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for sticky in [placed, unplaced] {
            let decoded = try decoder.decode(Sticky.self, from: encoder.encode(sticky))
            #expect(decoded == sticky)
        }
        #expect(unplaced.frame == nil)
        #expect(unplaced.floatsOnTop)
    }

    @Test("An edit keeps the creation time and moves the update time")
    func editBumpsUpdate() {
        var sticky = Sticky(text: "Buy milk", createdAt: instant)
        let later = instant.addingTimeInterval(60)

        sticky.edit(text: "Buy oat milk", at: later)

        #expect(sticky.text == "Buy oat milk")
        #expect(sticky.createdAt == instant)
        #expect(sticky.updatedAt == later)
    }

    @Test("An edit that changes nothing leaves the update time alone")
    func unchangedEditIsIgnored() {
        var sticky = Sticky(text: "Buy milk", createdAt: instant)

        sticky.edit(text: "Buy milk", at: instant.addingTimeInterval(60))

        #expect(sticky.updatedAt == instant)
    }

    @Test("Only blank text counts as empty")
    func emptiness() {
        #expect(Sticky(text: "").isEmpty)
        #expect(Sticky(text: " \n\t").isEmpty)
        #expect(!Sticky(text: " a ").isEmpty)
    }

    @Test("Legacy notes decode with defaults and preserve all their contents")
    func legacyDefaults() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","text":"Olá 😀\\nSecond line",
        "createdAt":"2027-01-15T08:00:00Z","updatedAt":"2027-01-15T08:01:00Z",
        "frame":{"x":10,"y":20,"width":260,"height":200},"floatsOnTop":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sticky = try decoder.decode(Sticky.self, from: Data(json.utf8))

        #expect(sticky.id == id)
        #expect(sticky.text == "Olá 😀\nSecond line")
        #expect(sticky.frame == StickyFrame(x: 10, y: 20, width: 260, height: 200))
        #expect(!sticky.floatsOnTop)
        #expect(sticky.updatedAt.timeIntervalSince(sticky.createdAt) == 60)
        #expect(sticky.color == .clear)
        #expect(!sticky.isCollapsed)
        #expect(!sticky.appearsOnAllSpaces)
        #expect(sticky.deletedAt == nil)
        #expect(sticky.richText == nil)
    }

    @Test("Rich UTF-16 emphasis round-trips emoji and composed text")
    func richUnicodeRoundTrip() throws {
        let text = "A😀 cafe\u{301}\nSecond line"
        let emoji = (text as NSString).range(of: "😀")
        let word = (text as NSString).range(of: "cafe\u{301}")
        let richText = StickyRichText(runs: [
            StickyTextRun(location: emoji.location, length: emoji.length, bold: true),
            StickyTextRun(location: word.location, length: word.length, italic: true),
        ])
        let sticky = Sticky(
            text: text, createdAt: instant, color: .purple,
            isCollapsed: true, appearsOnAllSpaces: true,
            deletedAt: instant.addingTimeInterval(60), richText: richText
        )
        let encoded = try JSONEncoder().encode(sticky)

        #expect(try JSONDecoder().decode(Sticky.self, from: encoded) == sticky)
        #expect(sticky.richText == richText)
        #expect(emoji.length == 2)
        #expect(sticky.title == "A😀 cafe\u{301}")
    }

    @Test("Malformed ranges are dropped without changing Unicode text")
    func invalidEmphasisRanges() {
        let text = "A😀B"
        let valid = StickyTextRun(location: 1, length: 2, bold: true)
        let richText = StickyRichText(runs: [
            valid,
            StickyTextRun(location: 2, length: 1, italic: true), // Inside a surrogate pair.
            StickyTextRun(location: -1, length: 2, bold: true),
            StickyTextRun(location: 0, length: Int.max, bold: true),
            StickyTextRun(location: 4, length: 1, italic: true),
            StickyTextRun(location: 0, length: 1),
        ])
        let sticky = Sticky(text: text, richText: richText)

        #expect(sticky.text == text)
        #expect(sticky.richText?.runs == [valid])
    }

    @Test("Formatting-only edits save, and plain edits clear stale ranges")
    func editsFormatting() {
        var sticky = Sticky(text: "Hello", createdAt: instant)
        let richText = StickyRichText(runs: [StickyTextRun(location: 0, length: 5, bold: true)])
        sticky.edit(text: "Hello", richText: richText, at: instant.addingTimeInterval(1))
        #expect(sticky.richText == richText)
        #expect(sticky.updatedAt == instant.addingTimeInterval(1))

        sticky.edit(text: "Hello", at: instant.addingTimeInterval(2))
        #expect(sticky.richText == richText)
        #expect(sticky.updatedAt == instant.addingTimeInterval(1))

        sticky.edit(text: "Hi", at: instant.addingTimeInterval(3))
        #expect(sticky.richText == nil)
        #expect(sticky.updatedAt == instant.addingTimeInterval(3))
    }

    @Test("The title comes only from the first line")
    func firstLineTitle() {
        #expect(Sticky(text: "  Shopping  \r\nMilk").title == "Shopping")
        #expect(Sticky(text: "\nMilk").title == Sticky(text: "").title)
        #expect(Sticky(text: "Ideas\n\nDetails").title == "Ideas")
    }

    @Test("An edit cannot move an existing update timestamp backwards")
    func updateTimeRemainsMonotonic() {
        var sticky = Sticky(text: "One", createdAt: instant)
        let latest = instant.addingTimeInterval(60)
        sticky.edit(text: "Two", at: latest)
        sticky.edit(text: "Three", at: instant.addingTimeInterval(10))
        #expect(sticky.text == "Three")
        #expect(sticky.updatedAt == latest)

        sticky.edit(
            text: "Three",
            richText: StickyRichText(runs: [StickyTextRun(location: 0, length: 5, italic: true)]),
            at: instant
        )
        #expect(sticky.updatedAt == latest)
    }

    @Test("Overlapping emphasis combines bold and italic without losing either style")
    func overlappingEmphasis() {
        let text = "A😀BCD"
        let richText = StickyRichText(runs: [
            StickyTextRun(location: 0, length: 5, bold: true),
            StickyTextRun(location: 1, length: 5, italic: true),
            StickyTextRun(location: 0, length: 5, bold: true),
        ])
        let normalized = richText.normalized(for: text)
        #expect(normalized.runs == [
            StickyTextRun(location: 0, length: 1, bold: true),
            StickyTextRun(location: 1, length: 4, bold: true, italic: true),
            StickyTextRun(location: 5, length: 1, italic: true),
        ])
        #expect(normalized.normalized(for: text) == normalized)
    }
}
