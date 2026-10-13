import AppKit
import Testing
@testable import StickyUI

@MainActor
@Suite("Independent system sharing requests")
struct NotesShareOperationTests {
    private func service() -> NSSharingService {
        NSSharingService(title: "Test share", image: NSImage(size: .init(width: 1, height: 1)), alternateImage: nil) {}
    }

    @Test("A late callback from a cancelled request cannot complete a newer request")
    func lateCallback() {
        let oldService = service()
        let newService = service()
        var oldOutcomes: [NotesSharingAvailability.Outcome] = []
        var newOutcomes: [NotesSharingAvailability.Outcome] = []
        let old = NotesShareOperation(route: .notes) { oldOutcomes.append($0) }
        let new = NotesShareOperation(route: .picker) { newOutcomes.append($0) }
        old.use(oldService)
        old.cancel()
        new.use(newService)

        old.sharingService(oldService, didShareItems: ["Old"])
        new.sharingService(oldService, didShareItems: ["Old"])
        #expect(oldOutcomes == [.cancelled])
        #expect(newOutcomes.isEmpty)
        new.sharingService(newService, didShareItems: ["New"])
        #expect(newOutcomes == [.sent(.picker)])
    }

    @Test("Completing or cancelling a request invokes its callback once")
    func completionOnce() {
        let service = service()
        var outcomes: [NotesSharingAvailability.Outcome] = []
        let operation = NotesShareOperation(route: .notes) { outcomes.append($0) }
        operation.use(service)
        operation.sharingService(service, didShareItems: ["Saved"])
        operation.sharingService(service, didShareItems: ["Saved"])
        operation.cancel()
        #expect(outcomes == [.sent(.notes)])
    }
}
