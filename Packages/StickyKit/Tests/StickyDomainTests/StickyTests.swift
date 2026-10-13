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
}
