import StickyStorage
import SwiftUI
import WidgetKit

struct ScrapsCaptureWidget: Widget {
    let kind = "com.joaocosta.Scraps.capture"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuickCaptureConfiguration.self, provider: ScrapsCaptureProvider()) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Label("Scraps", systemImage: "note.text").font(.headline)
                Spacer(minLength: 0)
                Link(destination: StickyNavigation.new.url) {
                    Label("New Sticky", systemImage: "plus").font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Link(destination: StickyNavigation.library.url) {
                    Label("Your Stickies", systemImage: "square.grid.2x2")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .containerBackground(Color.accentColor.opacity(0.12), for: .widget)
            .widgetURL(StickyNavigation.new.url)
        }
        .configurationDisplayName("Quick capture")
        .description("Create a sticky without losing a thought.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
