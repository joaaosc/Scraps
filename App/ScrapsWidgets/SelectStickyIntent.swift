import AppIntents

struct SelectStickyIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a sticky"
    static let description = IntentDescription("Keep a specific sticky, or your latest pinned note, close by.")
    static let isDiscoverable = false
    @Parameter(title: "Sticky") var note: WidgetStickyEntity?
    @Parameter(title: "Show checklist", default: true) var showsChecklist: Bool
}

struct QuickCaptureConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Quick capture"
    static let isDiscoverable = false
}
