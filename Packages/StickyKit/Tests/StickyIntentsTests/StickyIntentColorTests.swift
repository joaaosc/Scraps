import StickyDomain
import StickyIntents
import Testing

@Suite("System color parameter")
struct StickyIntentColorTests {
    @Test("Every system color maps back to the same shared palette color")
    func paletteMapping() {
        #expect(StickyIntentColor.allCases.map(\.stickyColor) == StickyColor.allCases)
        for color in StickyColor.allCases {
            let parameter = StickyIntentColor(color)
            #expect(parameter.stickyColor == color)
            #expect(StickyIntentColor.caseDisplayRepresentations[parameter] != nil)
        }
    }

    @Test("An omitted color stays optional while supplied colors reach the parameter")
    func optionalParameter() {
        #expect(NewStickyIntent(text: nil).color == nil)
        #expect(NewStickyIntent(text: "A thought", color: .purple).color?.stickyColor == .purple)
    }
}
