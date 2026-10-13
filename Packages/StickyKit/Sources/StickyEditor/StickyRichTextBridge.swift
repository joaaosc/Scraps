import Foundation
import StickyDomain
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Keeps the native editor, portable emphasis runs and system sharing in sync.
/// Only UTF-16 offsets are persisted; platform font archives never enter storage.
public enum StickyRichTextBridge {
    public static func attributedText(text: String, richText: StickyRichText?) -> AttributedString {
        var result = AttributedString(text)
        let runs = richText?.normalized(for: text).runs ?? []
        let boundaries = Set(runs.flatMap { [$0.location, $0.location + $0.length] })
        var positions: [Int: AttributedString.Index] = [:]
        var offset = 0
        for index in result.unicodeScalars.indices {
            if boundaries.contains(offset) { positions[offset] = index }
            offset += result.unicodeScalars[index].value > 0xFFFF ? 2 : 1
        }
        positions[offset] = result.endIndex
        for run in runs {
            // Use the attributed string's scalar indices directly: converting
            // String.Index still rejects positions inside composed characters.
            guard let lower = positions[run.location], let upper = positions[run.location + run.length] else { continue }
            result[lower..<upper].font = canonicalFont(bold: run.bold, italic: run.italic)
        }
        return result
    }

    public static func richText(
        from text: AttributedString,
        in context: Font.Context
    ) -> StickyRichText? {
        var runs: [StickyTextRun] = []
        var location = 0
        for run in text.runs {
            let length = text[run.range].unicodeScalars.reduce(0) { $0 + ($1.value > 0xFFFF ? 2 : 1) }
            defer { location += length }
            guard let font = run.font else { continue }
            let style = emphasis(of: font, in: context)
            guard style.bold || style.italic else { continue }
            let value = StickyTextRun(
                location: location, length: length,
                bold: style.bold, italic: style.italic
            )
            if let previous = runs.last,
               previous.location + previous.length == value.location,
               previous.bold == value.bold, previous.italic == value.italic {
                runs[runs.count - 1].length += value.length
            } else {
                runs.append(value)
            }
        }
        return runs.isEmpty ? nil : StickyRichText(runs: runs)
    }

    static func canonicalFont(bold: Bool, italic: Bool) -> Font {
        switch (bold, italic) {
        case (false, false): .body
        case (true, false): .body.bold()
        case (false, true): .body.italic()
        case (true, true): .body.bold().italic()
        }
    }

    static func emphasis(of font: Font, in context: Font.Context) -> (bold: Bool, italic: Bool) {
        // Explicit semantic styles remain independent of accessibility font
        // settings; appearance alone must never turn plain text into bold data.
        if font == .body { return (false, false) }
        if font == .body.bold() { return (true, false) }
        if font == .body.italic() { return (false, true) }
        if font == .body.bold().italic() { return (true, true) }
        let resolved = font.resolve(in: context)
        return (resolved.isBold, resolved.isItalic)
    }

    /// A native attributed string for Notes and the pasteboard, with real fonts.
    @MainActor
    public static func foundationText(text: String, richText: StickyRichText?) -> NSAttributedString {
        #if os(macOS)
        let base = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        #else
        let base = UIFont.preferredFont(forTextStyle: .body)
        #endif
        let result = NSMutableAttributedString(string: text, attributes: [.font: base])
        for run in richText?.normalized(for: text).runs ?? [] {
            #if os(macOS)
            var traits: NSFontTraitMask = []
            if run.bold { traits.insert(.boldFontMask) }
            if run.italic { traits.insert(.italicFontMask) }
            let font = NSFontManager.shared.convert(base, toHaveTrait: traits)
            #else
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.bold { traits.insert(.traitBold) }
            if run.italic { traits.insert(.traitItalic) }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
            let font = UIFont(descriptor: descriptor, size: 0)
            #endif
            result.addAttribute(
                .font, value: font,
                range: NSRange(location: run.location, length: run.length)
            )
        }
        return result
    }

    /// Offers RTF alongside plain text so pasting into Notes preserves emphasis.
    @MainActor
    public static func copyToPasteboard(text: String, richText: StickyRichText?) {
        let attributed = foundationText(text: text, richText: richText)
        let rtf = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        #if os(macOS)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let rtf { item.setData(rtf, forType: .rtf) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        #else
        var item: [String: Any] = ["public.utf8-plain-text": text]
        if let rtf { item["public.rtf"] = rtf }
        UIPasteboard.general.items = [item]
        #endif
    }
}
