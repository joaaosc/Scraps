import Foundation
import StickyDomain
import StickyStorage
import WidgetKit

struct ScrapsWidgetEntry: TimelineEntry {
    let date: Date
    let note: Sticky?
    let showsChecklist: Bool
    let noteCount: Int
}

struct ScrapsNoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScrapsWidgetEntry {
        .init(date: Date(), note: Sticky(text: String(localized: "A little space for your thoughts"), color: .yellow), showsChecklist: true, noteCount: 1)
    }
    func snapshot(for configuration: SelectStickyIntent, in context: Context) async -> ScrapsWidgetEntry {
        await entry(for: configuration)
    }
    func timeline(for configuration: SelectStickyIntent, in context: Context) async -> Timeline<ScrapsWidgetEntry> {
        let entry = await entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
    private func entry(for configuration: SelectStickyIntent) async -> ScrapsWidgetEntry {
        let notes = await widgetNotes()
        let note: Sticky?
        if let selected = configuration.note { note = notes.first { $0.id == selected.id } }
        else { note = notes.first }
        return .init(date: Date(), note: note, showsChecklist: configuration.showsChecklist, noteCount: notes.count)
    }
}

struct ScrapsCaptureProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScrapsWidgetEntry {
        .init(date: Date(), note: nil, showsChecklist: false, noteCount: 0)
    }
    func snapshot(for configuration: QuickCaptureConfiguration, in context: Context) async -> ScrapsWidgetEntry {
        .init(date: Date(), note: nil, showsChecklist: false, noteCount: await widgetNotes().count)
    }
    func timeline(for configuration: QuickCaptureConfiguration, in context: Context) async -> Timeline<ScrapsWidgetEntry> {
        let entry = await snapshot(for: configuration, in: context)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
}

private func widgetNotes() async -> [Sticky] {
    do {
        let store = try FileStickyStore(directoryURL: StickyAppStorage.sharedDirectoryURL())
        return try await store.stickies().filter { !$0.isArchived }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    } catch { return [] }
}
