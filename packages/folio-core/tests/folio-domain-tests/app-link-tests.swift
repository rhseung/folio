import FolioDomain
import Foundation
import PropertyBased
import Testing

struct AppLinkTests {
    let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func writesTheIssuesShape() {
        #expect(AppLink(.assignment, id).string == "folio://assignment/6F9619FF-8B86-D011-B42D-00C04FC964FF")
        #expect(AppLink(.material, id, anchor: .page(12)).string == "folio://material/6F9619FF-8B86-D011-B42D-00C04FC964FF#page=12")
        #expect(AppLink(.note, id, anchor: .block("eq-1")).string.hasSuffix("#^eq-1"))
        #expect(AppLink.place(.today).string == "folio://today")
        #expect(AppLink.course(id, page: .materials).string == "folio://course/6F9619FF-8B86-D011-B42D-00C04FC964FF/materials")
        #expect(AppLink(.problemSet, id).string.hasPrefix("folio://problem-set/"))
    }

    /// A recording's address carries where it is playing, written as the player shows it.
    @Test func aRecordingKeepsItsMoment() {
        #expect(AppLink(.recording, id, anchor: .time(750)).string.hasSuffix("#t=12:30"))
        #expect(AppLink(.recording, id, anchor: .time(3723)).string.hasSuffix("#t=1:02:03"))
        #expect(AppLink(.recording, id, anchor: .time(5)).string.hasSuffix("#t=0:05"))
        let r = "folio://recording/\(id.uuidString)"
        #expect(AppLink(string: r + "#t=12:30") == AppLink(.recording, id, anchor: .time(750)))
        #expect(AppLink(string: r + "#t=750") == AppLink(.recording, id, anchor: .time(750)))
        #expect(AppLink(string: r + "#t=1:02:03") == AppLink(.recording, id, anchor: .time(3723)))
        #expect(AppLink(string: r + "#t=") == AppLink(.recording, id))
        #expect(AppLink(string: r + "#t=12:30")?.withoutAnchor == AppLink(.recording, id))

        // A moment means nothing to a note, and a note's heading that reads like one stays a heading.
        #expect(AppLink(string: "folio://note/\(id.uuidString)#t=1:00") == AppLink(.note, id, anchor: .heading("t=1:00")))
        let heading = AppLink(.note, id, anchor: .heading("t=1:00"))
        #expect(AppLink(string: heading.string) == heading)
    }

    @Test func headingsAreEscapedSoTheyEndWhereLinksInTextEnd() {
        let link = AppLink(.note, id, anchor: .heading("매칭 (정의)"))
        #expect(!link.string.contains(" ") && !link.string.contains("(") && !link.string.contains(")"))
        #expect(AppLink(string: link.string) == link)
        // A heading that reads like a block or a page stays a heading.
        for heading in ["^x", "page=3", "100%", "a#b"] {
            let l = AppLink(.note, id, anchor: .heading(heading))
            #expect(AppLink(string: l.string)?.anchor == .heading(heading))
        }
    }

    /// Foundation escapes a block's `^` in the URL; the block comes back a block, not a heading.
    @Test func aBlockSurvivesTheURL() throws {
        let link = AppLink(.note, UUID(), anchor: .block("proof"))
        #expect(link.url.absoluteString.hasSuffix("#%5Eproof"))
        #expect(AppLink(url: link.url) == link)
        let heading = AppLink(.note, UUID(), anchor: .heading("증명 끝"))
        #expect(AppLink(url: heading.url) == heading)
    }

    @Test func readsWhatTheNotePreviewHandsIt() {
        // The renderer writes a wiki link's heading raw; a lower-case ID is still the ID.
        let raw = "folio://note/\(id.uuidString.lowercased())#정의 1"
        #expect(AppLink(string: raw) == AppLink(.note, id, anchor: .heading("정의 1")))
        #expect(AppLink(string: "FOLIO://Material/\(id.uuidString)#page=3") == AppLink(.material, id, anchor: .page(3)))
        #expect(AppLink(string: "folio://today/") == .place(.today))
        #expect(AppLink(string: "folio://course/\(id.uuidString)/overview") == .course(id))
    }

    @Test func settingsTabsArePathsLikeACoursesPages() {
        #expect(AppLink.settings(.claude).string == "folio://settings/claude")
        #expect(AppLink.settings(nil) == .place(.settings))
        #expect(AppLink(string: "folio://Settings/Review") == .settings(.review))
        #expect(AppLink(string: "folio://settings/class#x") == .settings(.classes))

        // Another tab is another step in a window's history.
        #expect(AppLink.settings(.claude).withoutAnchor != AppLink.settings(.general).withoutAnchor)
        #expect(AppLink.settings(.claude).with(.heading("x")) == .settings(.claude))
        #expect(AppLink(string: "folio://settings/nowhere") == nil)

        // Tabs #416 merged: old links open the tab that took them over, and are written by its name.
        #expect(AppLink(string: "folio://settings/profile") == .settings(.record))
        #expect(AppLink(string: "folio://Settings/Letters") == .settings(.record))
        #expect(AppLink(string: "folio://settings/recording")?.string == "folio://settings/class")
        #expect(AppLink(string: "folio://grades/claude") == nil)
    }

    @Test func dropsWhatTheKindHasNoUseFor() {
        #expect(AppLink(string: "folio://session/\(id.uuidString)#page=3") == AppLink(.session, id))
        #expect(AppLink(string: "folio://material/\(id.uuidString)#^block") == AppLink(.material, id))
        #expect(AppLink(string: "folio://material/\(id.uuidString)#page=0") == AppLink(.material, id))
        #expect(AppLink(string: "folio://grades#x") == .place(.grades))
        #expect(AppLink(string: "folio://note/\(id.uuidString)#^not a block") == AppLink(.note, id))
    }

    /// Each kind's facts agree with how its links are read and written: an anchor survives only on a kind that takes
    /// it, a page only on a kind that has pages, and only places go without an ID.
    @Test func eachKindsFactsShapeItsLinks() {
        let anchors: [AppLink.Anchor] = [.page(2), .block("b-1"), .heading("정의"), .time(90)]
        for kind in AppLink.Kind.allCases {
            #expect(kind.isPlace == (kind.home == .app))
            if kind.isPlace {
                #expect(AppLink(string: "folio://\(kind.rawValue)/\(id.uuidString)") == nil)
                continue
            }
            for anchor in anchors {
                let kept = AppLink(kind, id, anchor: anchor).anchor != nil
                #expect(kept == kind.anchors.contains(anchor.kind), "\(kind) \(anchor)")
            }
            let paged = AppLink(string: "folio://\(kind.rawValue)/\(id.uuidString)/materials")
            #expect((paged != nil) == kind.hasPages, "\(kind)")
        }

        #expect(AppLink(string: "folio://settings/claude") != nil && AppLink.Kind.settings.hasPages)
    }

    /// The Claude panel's buttons share the scheme; none of them may read as something to open.
    @Test func theActionHostIsNoKind() throws {
        #expect(AppLink.Kind(rawValue: AppLink.actionHost) == nil)
        let button = try #require(URL(string: "folio://action/copy/\(id.uuidString)"))
        #expect(AppLink(url: button) == nil && AppLink.isAction(button))
        #expect(!AppLink.isAction(AppLink(.exam, id).url))
    }

    @Test func aNoteNamedByTitleIsNoAppLink() throws {
        let titled = try #require(URL(string: "folio://note/%EB%A7%A4%EC%B9%AD%20%EC%A0%95%EB%A6%AC#%EC%A0%95%EC%9D%98"))
        #expect(AppLink(url: titled) == nil)
        #expect(AppLink.noteTitle(titled) == "매칭 정리")
        #expect(AppLink.noteTitle(AppLink(.note, id).url) == nil)
        #expect(AppLink.noteTitle(AppLink(.exam, id).url) == nil)
        #expect(AppLink.noteTitle(try #require(URL(string: "folio://action/copy/x"))) == nil)
    }

    @Test func refusesWhatIsNotALink() {
        for bad in ["", "folio://", "folio:/today", "https://today", "folio://nothing", "folio://today/\(id.uuidString)",
                    "folio://note/매칭 정리", "folio://note", "folio://exam/\(id.uuidString)/more", "folio://course/\(id.uuidString)/nowhere",
                    "obsidian://open?vault=Brain"] {
            #expect(AppLink(string: bad) == nil, "\(bad)")
        }
    }

    @Test func findsLinksWrittenInText() {
        let link = AppLink(.material, id, anchor: .page(4))
        let tex = "See \\href{\(link.string)}{the slides} and folio://grades."

        // The sentence's full stop isn't part of the address; a heading's last character is.
        #expect(AppLink.links(in: tex).map(\.link) == [link, .place(.grades)])
        #expect((tex as NSString).substring(with: AppLink.links(in: tex)[1].range) == "folio://grades")
        #expect(AppLink.links(in: "folio://exam/\(id.uuidString)!").map(\.link) == [AppLink(.exam, id)])
        #expect(AppLink.links(in: "folio://note/\(id.uuidString)#Intro.").map(\.link) == [AppLink(.note, id, anchor: .heading("Intro."))])

        // A page, time or block is still one at the end of a sentence.
        #expect(AppLink.links(in: "범위는 folio://material/\(id.uuidString)#page=12.").map(\.link) == [AppLink(.material, id, anchor: .page(12))])
        #expect(AppLink.links(in: "folio://recording/\(id.uuidString)#t=12:30.").map(\.link) == [AppLink(.recording, id, anchor: .time(750))])
        #expect(AppLink.links(in: "folio://note/\(id.uuidString)#^c1!").map(\.link) == [AppLink(.note, id, anchor: .block("c1"))])
        let at = (tex as NSString).range(of: "folio://material").location + 3
        #expect(AppLink.link(in: tex, at: at) == link)
        #expect(AppLink.link(in: tex, at: 1) == nil)
        let md = "[슬라이드](\(link.string)) 한글 folio://today"
        #expect(AppLink.links(in: md).map(\.link) == [link, .place(.today)])

        // Offsets count UTF-16 units, as text views do: the Hangul before the link shifts it by one unit each.
        let range = AppLink.links(in: md)[0].range
        #expect((md as NSString).substring(with: range) == link.string)
    }

    @Test func searchResultsOpenTheirItem() {
        let course = UUID()
        #expect(AppLink(SearchItem(kind: .quiz, courseId: course, id: id, title: "")) == AppLink(.card, id))
        #expect(AppLink(SearchItem(kind: .note, courseId: course, id: id, title: "")) == AppLink(.note, id))
        #expect(AppLink(SearchItem(kind: .exam, courseId: course, id: id, title: "")) == AppLink(.exam, id))
    }

    @Test func findsTheCourseThatHoldsATarget() {
        let device = UUID(), now = Date(timeIntervalSince1970: 1_790_000_000)
        var a = CourseFile(course: Course(device: device, at: now, title: "A"))
        let b = CourseFile(course: Course(device: device, at: now, title: "B"))
        let exam = Exam(device: device, at: now, title: "중간고사")
        a.exams.append(exam)
        let note = UUID()
        a.notes.append(NoteEntry(id: note, device: device, at: now, path: "Notes/매칭.md", meta: NoteMeta(id: note)))

        #expect(AppLink(.note, note).course(in: [b, a]) == a.course.id)
        #expect(AppLink(.exam, exam.id).course(in: [b, a]) == a.course.id)
        #expect(AppLink.course(b.course.id).course(in: [a, b]) == b.course.id)
        #expect(AppLink(.exam, UUID()).course(in: [a, b]) == nil)
        #expect(AppLink(.card, UUID()).course(in: [a, b]) == nil)

        let set = ProblemSet(device: device, at: now, title: "Exercise 1")
        a.problemSets.append(set)
        #expect(AppLink(.problemSet, set.id).course(in: [b, a]) == a.course.id)

        // What lives outside a course is never found in one, even by an ID a course happens to use.
        for kind in AppLink.Kind.allCases where !kind.isPlace && kind.home != .course {
            #expect(AppLink(kind, a.course.id).course(in: [a, b]) == nil, "\(kind)")
        }
    }

    @Test func codesAsItsAddress() throws {
        let link = AppLink(.note, id, anchor: .heading("증명"))
        let data = try JSONEncoder().encode([link])
        #expect(try JSONDecoder().decode([AppLink].self, from: data) == [link])
    }
}

/// What any link must keep, whatever it points at.
struct AppLinkPropertyTests {
    static let kind = Gen.element(of: AppLink.Kind.allCases).map { $0! }
    static let page = Gen.element(of: AppLink.CoursePage.allCases).map { $0! }
    static let uuid = Gen.uint64().array(of: 2).map { w -> UUID in
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: w[0] >> (i * 8)); bytes[8 + i] = UInt8(truncatingIfNeeded: w[1] >> (i * 8)) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    /// Hangul, Latin, digits, the characters links stop at, and the ones that mean block or page.
    static let text = Gen.oneOf(Gen.character(in: "가"..."힣"), Gen.character(in: " "..."~")).string(of: 0...12)
    static let anchor = Gen.int(in: 0...4).map { i -> Int in i }

    static func link(_ kind: AppLink.Kind, _ id: UUID, _ page: AppLink.CoursePage, _ choice: Int, _ n: Int, _ text: String) -> AppLink {
        if kind == .settings {
            let tabs: [AppLink.SettingsPage?] = [nil] + AppLink.SettingsPage.allCases
            return .settings(tabs[n % tabs.count])
        }
        if kind.isPlace { return .place(kind) }
        if kind == .course { return .course(id, page: page) }
        let anchor: AppLink.Anchor? = switch choice {
        case 1: .page(n)
        case 2: .block(text.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        // A heading starting with `^` would read as a block from a URL (see `init(url:)`).
        case 3: .heading(text.hasPrefix("^") ? "x" + text : text)
        case 4: .time(n * 37)
        default: nil
        }
        return AppLink(kind, id, anchor: anchor)
    }

    @Test func roundTripsThroughItsText() async {
        await propertyCheck(input: Self.kind, Self.uuid, Self.page, Self.anchor, Gen.int(in: 0...999), Self.text) { kind, id, page, choice, n, text in
            let link = Self.link(kind, id, page, choice, n, text)
            #expect(AppLink(string: link.string) == link)
            #expect(AppLink(url: link.url) == link)
        }
    }

    @Test func isFoundWholeInTheTextAroundIt() async {
        await propertyCheck(input: Self.kind, Self.uuid, Self.anchor, Gen.int(in: 1...999), Self.text, Self.text) { kind, id, choice, n, text, before in
            let link = Self.link(kind, id, .notes, choice, n, text)
            for written in ["[\(before)](\(link.string))", "\\href{\(link.string)}{\(before)}", "\(before) \(link.string)\n"] {
                #expect(AppLink.links(in: written).last?.link == link, "\(written)")
            }
        }
    }
}

struct LinkHistoryTests {
    @Test func goesBackAndForwardLikeABrowser() {
        var h = LinkHistory("a")
        h.visit("b")
        h.visit("c")
        let back = h.goBack()

        #expect(back && h.current == "b" && h.forward == ["c"])
        h.visit("d")
        #expect(h.back == ["a", "b"] && h.forward.isEmpty)
        let twice = h.goBack(2)
        #expect(twice && h.current == "a" && h.forward == ["b", "d"])
        let past = h.goBack()
        #expect(!past)
        let ahead = h.goForward(2)
        #expect(ahead && h.current == "d")
    }

    @Test func theSamePlaceAgainIsNoStep() {
        var h = LinkHistory("a")
        h.visit("a")
        #expect(!h.canGoBack)
        h.replace("a2")
        #expect(!h.canGoBack && h.current == "a2")
    }

    @Test func keepsOnlyTheNewestSteps() {
        var h = LinkHistory(0, limit: 3)
        for i in 1...10 { h.visit(i) }
        #expect(h.back == [7, 8, 9])
    }

    static let steps = Gen.int(in: 0...20).array(of: 0...40)

    @Test func backThenForwardReturns() async {
        await propertyCheck(input: Self.steps, Gen.int(in: 0...40)) { visits, k in
            var h = LinkHistory(-1, limit: 16)
            for v in visits { h.visit(v) }
            let before = h
            let n = min(k, h.back.count)
            let wentBack = h.goBack(n)
            #expect(wentBack == (n >= 1))
            if n >= 1 {
                let wentForward = h.goForward(n)
                #expect(wentForward)
            }
            #expect(h.current == before.current && h.back == before.back)
            #expect(h.back.count <= 16)
            #expect(zip(h.back, h.back.dropFirst() + [h.current]).allSatisfy { $0 != $1 })
        }
    }
}
