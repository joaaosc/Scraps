import AppIntents
import Foundation
import StickyDomain
@testable import StickyIntents
import Testing

@Suite("Spotlight action entities")
struct StickyActionEntityTests {
    @Test("Entity identifiers and ranking match the fixed action catalog")
    func entities() {
        for action in StickyAction.allCases {
            let entity = StickyActionEntity(action: action)
            #expect(entity.id == action.rawValue)
            #expect(entity.attributeSet.rankingHint?.intValue == action.priority)
            #expect(entity.attributeSet.textContent == nil)
            #expect(entity.attributeSet.contentDescription == nil)
        }
    }

    @Test("All query paths preserve the same fixed order")
    func queries() async throws {
        let query = StickyActionQuery()
        let suggested = try await query.suggestedEntities()
        let filtered = try await query.entities(matching: "sticky")
        let identified = try await query.entities(for: ["settings", "new-sticky", "unknown"])
        #expect(suggested.map(\.action) == StickyAction.allCases)
        #expect(filtered.map(\.action) == [.newSticky, .newSessionSticky, .newStickyInColor])
        #expect(identified.map(\.action) == [.newSticky, .settings])
    }

    @Test("Queries recognize supported languages independently of the displayed language")
    func multilingualQueries() {
        let names: [StickyAction: [String]] = [
            .newSticky: ["New Sticky", "Nova nota"],
            .newSessionSticky: ["New Sticky (This Session Only)", "Nova nota (só nesta sessão)"],
            .newStickyInColor: ["New Sticky in Color…", "Nova nota com cor…"],
            .settings: ["Settings", "Ajustes"],
        ]
        #expect(StickyActionQuery.matchingActions("nova nota", localizedNames: names) == [
            .newSticky, .newSessionSticky, .newStickyInColor,
        ])
        #expect(StickyActionQuery.matchingActions("sessao", localizedNames: names) == [.newSessionSticky])
        #expect(StickyActionQuery.matchingActions("ajustes", localizedNames: names) == [.settings])
        #expect(StickyActionQuery.matchingActions("new sticky", localizedNames: names) == [
            .newSticky, .newSessionSticky, .newStickyInColor,
        ])
        #expect(StickyActionQuery.matchingActions("Call Ana tomorrow", localizedNames: names) == [])
    }

    @Test("User activities resolve this entity type and reject unknown IDs")
    func activities() {
        let known = NSUserActivity(activityType: "test.action")
        known.appEntityIdentifier = EntityIdentifier(
            for: StickyActionEntity.self,
            identifier: StickyAction.settings.rawValue
        )
        #expect(StickyActionEntity.action(from: known) == .settings)

        let unknown = NSUserActivity(activityType: "test.action")
        unknown.appEntityIdentifier = EntityIdentifier(
            for: StickyActionEntity.self,
            identifier: "a-persons-note"
        )
        #expect(StickyActionEntity.action(from: unknown) == nil)
        #expect(StickyActionEntity.action(from: NSUserActivity(activityType: "unrelated")) == nil)
    }
}
