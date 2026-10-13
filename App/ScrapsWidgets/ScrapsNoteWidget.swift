import AppIntents
import StickyDomain
import StickyEditor
import StickyStorage
import SwiftUI
import WidgetKit

struct ScrapsNoteWidget: Widget {
    let kind = "com.joaocosta.Scraps.note"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectStickyIntent.self, provider: ScrapsNoteProvider()) { entry in
            ScrapsNoteWidgetView(entry: entry)
                .containerBackground(for: .widget) { widgetColor(entry.note?.color ?? .clear).opacity(0.2) }
        }
        .configurationDisplayName("Sticky")
        .description("Your ideas and checklists, on your desktop or Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ScrapsNoteWidgetView: View {
    let entry: ScrapsWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let note = entry.note {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "note.text").foregroundStyle(widgetColor(note.color))
                        .accessibilityHidden(true)
                    Text(note.title).font(.headline).lineLimit(1)
                    if note.isPinned { Image(systemName: "pin.fill").accessibilityLabel("Favorite") }
                }
                let items = StickyChecklist.items(in: note.text)
                if entry.showsChecklist, !items.isEmpty {
                    ForEach(Array(items.prefix(family == .systemLarge ? 5 : family == .systemSmall ? 2 : 3))) { item in
                        Button(intent: ToggleStickyChecklistIntent(noteID: note.id, location: item.location, expectedLine: item.line)) {
                            Label(item.text, systemImage: item.completed ? "checkmark.circle.fill" : "circle")
                                .lineLimit(2)
                                .strikethrough(item.completed)
                                .foregroundStyle(item.completed ? .secondary : .primary)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 32, alignment: .leading)
                        .accessibilityLabel(item.text)
                        .accessibilityValue(item.completed ? String(localized: "Completed") : String(localized: "Not completed"))
                    }
                } else {
                    Text(StickyRichTextBridge.attributedText(text: note.text, richText: note.richText))
                        .font(.body)
                        .lineLimit(family == .systemLarge ? 14 : 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                if !note.tags.isEmpty {
                    Text(note.tags.map { "#" + $0 }.joined(separator: " "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .privacySensitive()
            .widgetURL(StickyNavigation.note(note.id).url)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Scraps", systemImage: "note.text").font(.headline)
                Text("Choose a sticky in the widget settings, or create your first note.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .widgetURL(StickyNavigation.library.url)
        }
    }
}

func widgetColor(_ color: StickyColor) -> Color {
    switch color {
    case .clear: .accentColor
    case .yellow: .yellow
    case .blue: .blue
    case .green: .green
    case .pink: .pink
    case .purple: .purple
    case .gray: .gray
    }
}
