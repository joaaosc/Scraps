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
            result[lower..<upper].font = canonicalFont(style: run.style, bold: run.bold, italic: run.italic)
            result[lower..<upper].underlineStyle = run.underline ? .single : nil
            result[lower..<upper].strikethroughStyle = run.strikethrough ? .single : nil
            result[lower..<upper].backgroundColor = run.highlight ? .yellow.opacity(0.28) : nil
            result[lower..<upper].link = run.link
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
            let style = emphasis(of: run.font ?? .body, in: context)
            let value = StickyTextRun(
                location: location, length: length,
                bold: style.bold, italic: style.italic,
                underline: run.underlineStyle != nil, strikethrough: run.strikethroughStyle != nil,
                highlight: run.backgroundColor != nil, style: style.style, link: run.link
            )
            guard value.hasFormatting else { continue }
            if let previous = runs.last,
               previous.location + previous.length == value.location,
               sameAttributes(previous, value) {
                runs[runs.count - 1].length += value.length
            } else {
                runs.append(value)
            }
        }
        return runs.isEmpty ? nil : StickyRichText(runs: runs)
    }

    static func canonicalFont(style: StickyTextStyle = .body, bold: Bool, italic: Bool) -> Font {
        var font: Font
        switch style {
        case .body: font = .body
        case .title: font = .title2
        case .heading: font = .headline
        case .caption: font = .caption
        case .code: font = .system(.body, design: .monospaced)
        }
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }

    static var supportedFonts: [Font?] {
        [nil] + StickyTextStyle.allCases.flatMap { style in
            [(false, false), (true, false), (false, true), (true, true)].map {
                Optional(canonicalFont(style: style, bold: $0.0, italic: $0.1))
            }
        }
    }

    static func emphasis(of font: Font, in context: Font.Context) -> (bold: Bool, italic: Bool, style: StickyTextStyle) {
        for style in StickyTextStyle.allCases {
            for emphasis in [(false, false), (true, false), (false, true), (true, true)] {
                if font == canonicalFont(style: style, bold: emphasis.0, italic: emphasis.1) {
                    return (emphasis.0, emphasis.1, style)
                }
            }
        }
        let resolved = font.resolve(in: context)
        return (resolved.isBold, resolved.isItalic, .body)
    }

    private static func sameAttributes(_ lhs: StickyTextRun, _ rhs: StickyTextRun) -> Bool {
        var lhs = lhs
        var rhs = rhs
        lhs.location = 0; lhs.length = 1
        rhs.location = 0; rhs.length = 1
        return lhs == rhs
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
            let size: NSFont.TextStyle
            switch run.style {
            case .body, .code: size = .body
            case .title: size = .title2
            case .heading: size = .headline
            case .caption: size = .caption1
            }
            let preferred = NSFont.preferredFont(forTextStyle: size)
            let base = run.style == .code ? NSFont.monospacedSystemFont(ofSize: preferred.pointSize, weight: .regular) : preferred
            var traits: NSFontTraitMask = []
            if run.bold { traits.insert(.boldFontMask) }
            if run.italic { traits.insert(.italicFontMask) }
            let font = NSFontManager.shared.convert(base, toHaveTrait: traits)
            #else
            let size: UIFont.TextStyle
            switch run.style {
            case .body, .code: size = .body
            case .title: size = .title2
            case .heading: size = .headline
            case .caption: size = .caption1
            }
            let preferred = UIFont.preferredFont(forTextStyle: size)
            let base = run.style == .code ? UIFont.monospacedSystemFont(ofSize: preferred.pointSize, weight: .regular) : preferred
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.bold { traits.insert(.traitBold) }
            if run.italic { traits.insert(.traitItalic) }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
            let font = UIFont(descriptor: descriptor, size: 0)
            #endif
            let range = NSRange(location: run.location, length: run.length)
            result.addAttribute(.font, value: font, range: range)
            if run.underline { result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if run.strikethrough { result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if let link = run.link { result.addAttribute(.link, value: link, range: range) }
            if run.highlight {
                #if os(macOS)
                let highlight = NSColor.systemYellow.withAlphaComponent(0.28)
                #else
                let highlight = UIColor.systemYellow.withAlphaComponent(0.28)
                #endif
                result.addAttribute(.backgroundColor, value: highlight, range: range)
            }
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
