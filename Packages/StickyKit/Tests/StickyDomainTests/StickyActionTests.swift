import StickyDomain
import Testing

@Suite("Fixed Spotlight actions")
struct StickyActionTests {
    @Test("The catalog contains exactly four actions in the requested order")
    func fixedCatalog() {
        #expect(StickyAction.allCases.map(\.title) == [
            "New Sticky",
            "New Sticky (This Session Only)",
            "New Sticky in Color…",
            "Settings",
        ])
        #expect(StickyAction.allCases.map(\.rawValue) == [
            "new-sticky", "new-session-sticky", "new-sticky-in-color", "settings",
        ])
        #expect(StickyAction.allCases.map(\.priority) == [100, 75, 50, 25])
    }

    @Test("Identifier lookup ignores stale IDs and duplicate requests")
    func resolvesIdentifiers() {
        #expect(StickyAction.identified(by: [
            "settings", "a-note-id", "new-sticky", "settings",
        ]) == [.newSticky, .settings])
        #expect(StickyAction.identified(by: []) == [])
    }

    @Test("Queries filter action names and preserve menu order")
    func queries() {
        #expect(StickyAction.matching("  \n ") == StickyAction.allCases)
        #expect(StickyAction.matching("NEW sticky") == [
            .newSticky, .newSessionSticky, .newStickyInColor,
        ])
        #expect(StickyAction.matching("only session") == [.newSessionSticky])
        #expect(StickyAction.matching("cólor") == [.newStickyInColor])
        #expect(StickyAction.matching("settings") == [.settings])
        #expect(StickyAction.matching("Call Ana tomorrow") == [])
        #expect(StickyAction.matching("apenas sessão", localizedTitles: [
            .newSessionSticky: "Nova nota (apenas nesta sessão)",
        ]) == [.newSessionSticky])
    }
}
