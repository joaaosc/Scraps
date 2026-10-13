import Foundation
import StickyDomain
import SwiftUI
import Testing
@testable import StickyEditor

#if os(macOS)
import AppKit
#endif

@MainActor
@Suite("Native rich text and portable notes")
struct StickyRichTextBridgeTests {
    private var context: Font.Context { EnvironmentValues().fontResolutionContext }

    @Test("Bold, italic and combined emphasis round-trip with UTF-16 Unicode offsets")
    func emphasisRoundTrip() throws {
        let text = "Plain 👩🏽‍💻 café Italic Both"
        let string = text as NSString
        func run(_ fragment: String, bold: Bool = false, italic: Bool = false) -> StickyTextRun {
            let range = string.range(of: fragment)
            return StickyTextRun(location: range.location, length: range.length, bold: bold, italic: italic)
        }
        let original = StickyRichText(runs: [
            run("👩🏽‍💻 café", bold: true),
            run("Italic", italic: true),
            run("Both", bold: true, italic: true),
        ])
        let persisted = try JSONDecoder().decode(
            StickyRichText.self, from: JSONEncoder().encode(original)
        )
        let native = StickyRichTextBridge.attributedText(text: text, richText: persisted)

        #expect(String(native.characters) == text)
        #expect(StickyRichTextBridge.richText(from: native, in: context) == original)
    }

    @Test("Unformatted text and explicit body text stay semantically plain")
    func plainTextHasNoEmphasis() {
        var text = AttributedString("A plain thought")
        #expect(StickyRichTextBridge.richText(from: text, in: context) == nil)

        text.font = .body

        #expect(StickyRichTextBridge.richText(from: text, in: context) == nil)
    }

    @Test("Scalar boundaries inside combining accents and emoji preserve their original emphasis")
    func emphasisInsideGraphemes() {
        let samples: [(String, StickyRichText)] = [
            ("e\u{301} café", StickyRichText(runs: [StickyTextRun(location: 1, length: 1, italic: true)])),
            ("👩🏽‍💻", StickyRichText(runs: [StickyTextRun(location: 2, length: 2, bold: true)])),
            ("مَرْحَبًا — שלום", StickyRichText(runs: [StickyTextRun(location: 1, length: 1, bold: true)])),
        ]
        for (text, emphasis) in samples {
            let native = StickyRichTextBridge.attributedText(text: text, richText: emphasis)
            #expect(String(native.characters) == text)
            #expect(StickyRichTextBridge.richText(from: native, in: context) == emphasis)
        }
    }

    @Test("Overlapping imported emphasis is combined before native display")
    func overlappingEmphasis() {
        let text = "Olá 😀 שלום"
        let rich = StickyRichText(runs: [
            StickyTextRun(location: 0, length: 6, bold: true),
            StickyTextRun(location: 4, length: 7, italic: true),
        ])
        let native = StickyRichTextBridge.attributedText(text: text, richText: rich)
        #expect(StickyRichTextBridge.richText(from: native, in: context) == rich.normalized(for: text))
    }

    @Test("Imported family and size become body text while preserving emphasis")
    func importedFontKeepsEmphasis() {
        var attributes = AttributeContainer()
        attributes.font = .system(size: 42, weight: .bold, design: .serif).italic()
        let definition = StickyFormattingDefinition(context: context)

        definition.constrain(&attributes)

        #expect(attributes.font == .body.bold().italic())
        let constrainedOnce = attributes
        definition.constrain(&attributes)
        #expect(attributes == constrainedOnce)
    }

    @Test("Every supported body style and absent font survive the formatting constraint")
    func canonicalStylesAreAllowed() {
        let definition = StickyFormattingDefinition(context: context)
        let fonts: [Font?] = [nil, .body, .body.bold(), .body.italic(), .body.bold().italic()]
        for font in fonts {
            var attributes = AttributeContainer()
            attributes.font = font

            definition.constrain(&attributes)

            #expect(attributes.font == font)
        }
    }

    @Test("Selection-aware emphasis changes preserve characters and existing italic text")
    func selectedEmphasis() throws {
        let plain = "Keep 👩🏽‍💻 café"
        let range = (plain as NSString).range(of: "👩🏽‍💻 café")
        var native = StickyRichTextBridge.attributedText(text: plain, richText: StickyRichText(runs: [
            StickyTextRun(location: range.location, length: range.length, italic: true),
        ]))
        let stringRange = try #require(Range(range, in: plain))
        let lower = try #require(AttributedString.Index(stringRange.lowerBound, within: native))
        let upper = try #require(AttributedString.Index(stringRange.upperBound, within: native))
        var selection = AttributedTextSelection(range: lower..<upper)
        let context = context

        native.transformAttributes(in: &selection) {
            let style = StickyRichTextBridge.emphasis(of: $0.font ?? .body, in: context)
            $0.font = StickyRichTextBridge.canonicalFont(bold: true, italic: style.italic)
        }

        #expect(String(native.characters) == plain)
        #expect(StickyRichTextBridge.richText(from: native, in: context)?.runs == [
            StickyTextRun(location: range.location, length: range.length, bold: true, italic: true),
        ])
        if case .ranges = selection.indices(in: native) {
            // The selection still belongs to its text after the transformation.
        } else {
            Issue.record("Formatting unexpectedly cleared the selected range")
        }
    }

    @Test("All semantic styles, links and decorations survive native editing and persistence")
    func fullFormattingRoundTrip() throws {
        let text = "👩🏽‍💻 café 東京"
        for style in StickyTextStyle.allCases {
            let rich = StickyRichText(runs: [StickyTextRun(location: 0, length: text.utf16.count, bold: true, italic: true, underline: true, strikethrough: true, highlight: true, style: style, link: URL(string: "https://example.com"))])
            let persisted = try JSONDecoder().decode(StickyRichText.self, from: JSONEncoder().encode(rich))
            let native = StickyRichTextBridge.attributedText(text: text, richText: persisted)
            #expect(StickyRichTextBridge.richText(from: native, in: context) == rich)
            var attributes = AttributeContainer()
            attributes.font = StickyRichTextBridge.canonicalFont(style: style, bold: true, italic: true)
            attributes.link = URL(string: "https://example.com")
            attributes.underlineStyle = .single
            let original = attributes
            StickyFormattingDefinition(context: context).constrain(&attributes)
            #expect(attributes == original)
        }
    }

    #if os(macOS)
    @Test("Sharing RTF preserves both text and real native font traits")
    func sharingRTF() throws {
        let text = "Bold italic"
        let formatting = StickyRichText(runs: [
            StickyTextRun(location: 0, length: 4, bold: true),
            StickyTextRun(location: 5, length: 6, italic: true),
        ])
        let native = StickyRichTextBridge.foundationText(text: text, richText: formatting)
        let data = try native.data(
            from: NSRange(location: 0, length: native.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let restored = try NSAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let bold = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let italic = try #require(restored.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)

        #expect(restored.string == text)
        #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        #expect(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
    }
    #endif
}
