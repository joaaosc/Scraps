import Foundation
import StickyDomain
import Testing

@Suite("Editing lists and checklists")
struct StickyListEditingTests {
    @Test("A cursor adds a bullet to its own line and moves with the content")
    func bulletAtCursor() {
        let result = StickyListEditing.toggle(
            .bullet, text: "Buy milk\nCall Ana", richText: nil,
            selection: NSRange(location: 12, length: 0)
        )

        #expect(result.text == "Buy milk\n• Call Ana")
        #expect(result.selection == NSRange(location: 14, length: 0))
        #expect(result.richText == nil)
    }

    @Test("Applying the same list style removes markers without changing indentation")
    func togglesMarkersOff() {
        let text = "  • First\n\t• Second"
        let result = StickyListEditing.toggle(
            .bullet, text: text, richText: nil,
            selection: NSRange(location: 0, length: text.utf16.count)
        )

        #expect(result.text == "  First\n\tSecond")
    }

    @Test("Numbering selected lines replaces existing markers")
    func numberedLines() {
        let text = "• One\n☐ Two\nThree"
        let result = StickyListEditing.toggle(
            .numbered, text: text, richText: nil,
            selection: NSRange(location: 0, length: text.utf16.count)
        )

        #expect(result.text == "1. One\n2. Two\n3. Three")
    }

    @Test("A selection ending at the next line leaves that line alone")
    func excludesUnselectedLine() {
        let result = StickyListEditing.toggle(
            .checklist, text: "First\nSecond\nThird", richText: nil,
            selection: NSRange(location: 0, length: 6)
        )

        #expect(result.text == "☐ First\nSecond\nThird")
    }

    @Test("Checking a selected checklist completes it and a second toggle reopens it")
    func checklistCompletion() {
        let text = "☐ Milk\n☑ Bread"
        let checked = StickyListEditing.toggleCompletion(
            text: text, richText: nil,
            selection: NSRange(location: 0, length: text.utf16.count)
        )
        let reopened = StickyListEditing.toggleCompletion(
            text: checked.text, richText: checked.richText, selection: checked.selection
        )

        #expect(checked.text == "☑ Milk\n☑ Bread")
        #expect(reopened.text == "☐ Milk\n☐ Bread")
    }

    @Test("List editing preserves emphasis across emoji and composed characters")
    func preservesUnicodeEmphasis() {
        let text = "👩🏽‍💻 café\nNext"
        let firstLength = "👩🏽‍💻 café".utf16.count
        let formatting = StickyRichText(runs: [
            StickyTextRun(location: 0, length: firstLength, bold: true),
            StickyTextRun(location: firstLength + 1, length: 4, italic: true),
        ])
        let result = StickyListEditing.toggle(
            .checklist, text: text, richText: formatting,
            selection: NSRange(location: 0, length: text.utf16.count)
        )

        #expect(result.text == "☐ 👩🏽‍💻 café\n☐ Next")
        #expect(result.richText?.runs == [
            StickyTextRun(location: 2, length: firstLength, bold: true),
            StickyTextRun(location: firstLength + 5, length: 4, italic: true),
        ])
    }

    @Test("Changing markers preserves bold text without making the marker bold")
    func replacesFormattedPrefix() {
        let result = StickyListEditing.toggle(
            .numbered, text: "• One", richText: StickyRichText(runs: [
                StickyTextRun(location: 0, length: 5, bold: true),
            ]), selection: NSRange(location: 3, length: 0)
        )

        #expect(result.text == "1. One")
        #expect(result.richText?.runs == [StickyTextRun(location: 3, length: 3, bold: true)])
        #expect(result.selection == NSRange(location: 4, length: 0))
    }

    @Test("An empty note and a trailing empty line can become list items")
    func emptyLines() {
        let empty = StickyListEditing.toggle(
            .bullet, text: "", richText: nil, selection: NSRange(location: 0, length: 0)
        )
        let trailing = StickyListEditing.toggle(
            .checklist, text: "First\n", richText: nil, selection: NSRange(location: 6, length: 0)
        )

        #expect(empty.text == "• ")
        #expect(empty.selection == NSRange(location: 2, length: 0))
        #expect(trailing.text == "First\n☐ ")
    }

    @Test("An invalid selection is clamped without overflowing")
    func invalidSelection() {
        let result = StickyListEditing.toggle(
            .bullet, text: "Text", richText: nil,
            selection: NSRange(location: Int.max, length: Int.max)
        )

        #expect(result.text == "• Text")
        #expect(result.selection == NSRange(location: 6, length: 0))
    }
}
