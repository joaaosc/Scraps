import AppIntents
import Foundation
import StickyDomain
import StickyStorage
import WidgetKit

struct ToggleStickyChecklistIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Checkmark"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = [.background]
    @Parameter(title: "Sticky") var noteID: String
    @Parameter(title: "Item") var location: Int
    @Parameter(title: "Text") var expectedLine: String

    init() {}
    init(noteID: UUID, location: Int, expectedLine: String) {
        self.noteID = noteID.uuidString
        self.location = location
        self.expectedLine = expectedLine
    }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: noteID), location >= 0 else { return .result() }
        let store = try FileStickyStore(directoryURL: StickyAppStorage.sharedDirectoryURL())
        guard var note = try await store.stickies().first(where: { $0.id == id }), !note.isArchived else { return .result() }
        guard let item = StickyChecklist.items(in: note.text).first(where: { $0.location == location }), item.line == expectedLine else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        let previous = note
        let result = StickyListEditing.toggleCompletion(text: note.text, richText: note.richText, selection: .init(location: location, length: item.line.utf16.count))
        note.edit(text: result.text, richText: result.richText)
        try await store.applySynchronized(note, replacing: previous)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
