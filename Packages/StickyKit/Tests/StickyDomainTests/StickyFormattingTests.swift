import Foundation
import StickyDomain
import Testing

@Suite("Portable formatting and widget checklists")
struct StickyFormattingTests {
    @Test("Older emphasis runs retain their style and unknown future styles remain readable")
    func legacyRuns() throws {
        let data = Data(#"{"location":0,"length":4,"bold":true,"style":"future"}"#.utf8)
        let run = try JSONDecoder().decode(StickyTextRun.self, from: data)
        #expect(run.bold && !run.underline && !run.highlight)
        #expect(run.style == .body && run.link == nil)
    }
    @Test("Links permit web, email and telephone destinations without local file access")
    func supportedLinks() {
        for link in ["https://example.com/東京", "mailto:hello@example.com", "tel:+5511999999999"] {
            #expect(StickyTextRun.safeLink(URL(string: link)) != nil)
        }
        for link in ["file:///private/secret", "javascript:alert(1)", "scraps://new", "https:"] {
            #expect(StickyTextRun.safeLink(URL(string: link)) == nil)
        }
    }
    @Test("List conversion preserves headings, highlights and links across Unicode text")
    func formattingSurvivesListEditing() {
        let text = "👩🏽‍💻 café"
        let run = StickyTextRun(location: 0, length: text.utf16.count, underline: true, strikethrough: true, highlight: true, style: .heading, link: URL(string: "https://example.com"))
        let result = StickyListEditing.toggle(.checklist, text: text, richText: StickyRichText(runs: [run]), selection: NSRange(location: 0, length: text.utf16.count))
        var shifted = run
        shifted.location = 2
        #expect(result.richText?.runs == [shifted])
    }
    @Test("Widget rows use original UTF-16 locations and accept Markdown checkboxes")
    func widgetRows() {
        let text = "👩🏽‍💻 ideas\n  - [ ] Buy café\n☑ 東京\n[x] Done"
        let rows = StickyChecklist.items(in: text)
        #expect(rows.count == 3)
        #expect(rows.first?.location == "👩🏽‍💻 ideas\n".utf16.count)
        #expect(rows.first?.line == "  - [ ] Buy café")
        #expect(rows.first?.text == "Buy café")
        #expect(rows.map(\.completed) == [false, true, true])
        let changed = StickyListEditing.toggleCompletion(text: text, richText: nil, selection: NSRange(location: rows[0].location, length: 0))
        #expect(StickyChecklist.items(in: changed.text).map(\.completed) == [true, true, true])
    }
    @Test("Collections keep archived notes separate and search Unicode tags")
    func collections() {
        let favorite = Sticky(text: "First", isPinned: true, tags: ["東京"])
        let recent = Sticky(text: "Newer", createdAt: favorite.createdAt.addingTimeInterval(60))
        let archived = Sticky(text: "Saved for later", isPinned: true, isArchived: true)
        let notes = [recent, archived, favorite]
        #expect(StickyCollection.notes.notes(in: notes).map(\.id) == [favorite.id, recent.id])
        #expect(StickyCollection.favorites.notes(in: notes).map(\.id) == [favorite.id])
        #expect(StickyCollection.archived.notes(in: notes).map(\.id) == [archived.id])
        #expect(StickyCollection.notes.notes(in: notes, search: "東京").map(\.id) == [favorite.id])
    }

}
