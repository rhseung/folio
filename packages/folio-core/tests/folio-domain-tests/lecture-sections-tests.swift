import FolioDomain
import Foundation
import PropertyBased
import Testing

struct LectureSectionsTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)

    /// Two lecture files and the units of a matchings chapter.
    func course() -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        file.materials = ["Lectures/05_Matchings.pdf", "Lectures/06_Flows.pdf"].map {
            Material(device: device, at: now, path: $0, role: MaterialRole(path: $0), status: .classified)
        }
        file.units = ["매칭", "König", "Hall", "Augmenting paths"].enumerated().map { i, t in
            Unit(device: device, at: now, title: t, order: i + 1)
        }
        return file
    }

    func pages(_ f: inout CourseFile, _ unit: Int, _ material: Int, _ range: ClosedRange<Int>) {
        f.units[unit].lecturePages.append(UnitPages(materialId: f.materials[material].id, firstPage: range.lowerBound, lastPage: range.upperBound))
    }

    // MARK: Zones

    @Test func zonesCutWhereTheUnitsChangeAndLeaveTheRestUnnamed() {
        var f = course()
        let m = f.materials[0].id
        pages(&f, 1, 0, 5...8)
        pages(&f, 2, 0, 9...13)
        // One unit across two files: its pages in the other file don't show here.
        pages(&f, 2, 1, 1...3)
        #expect(f.lectureZones(of: m, pageCount: 16) == [
            LectureZone(firstPage: 1, lastPage: 4, units: []),
            LectureZone(firstPage: 5, lastPage: 8, units: [f.units[1].id]),
            LectureZone(firstPage: 9, lastPage: 13, units: [f.units[2].id]),
            LectureZone(firstPage: 14, lastPage: 16, units: []),
        ])
        // Without the count the file ends where the last unit does.
        #expect(f.lectureZones(of: m, pageCount: nil).last == LectureZone(firstPage: 9, lastPage: 13, units: [f.units[2].id]))
        #expect(f.lectureZones(of: f.materials[1].id, pageCount: 10).first == LectureZone(firstPage: 1, lastPage: 3, units: [f.units[2].id]))
        #expect(f.isSplit(m) && f.isSplit(f.materials[1].id))
    }

    @Test func aFileNoUnitSplitsHasNoZones() {
        let f = course()
        #expect(f.lectureZones(of: f.materials[0].id, pageCount: 24).isEmpty)
        #expect(!f.isSplit(f.materials[0].id))
    }

    @Test func overlappingUnitsShareAZoneInOutlineOrder() {
        var f = course()
        pages(&f, 2, 0, 3...6)
        pages(&f, 1, 0, 1...4)
        #expect(f.lectureZones(of: f.materials[0].id, pageCount: 6) == [
            LectureZone(firstPage: 1, lastPage: 2, units: [f.units[1].id]),
            LectureZone(firstPage: 3, lastPage: 4, units: [f.units[1].id, f.units[2].id]),
            LectureZone(firstPage: 5, lastPage: 6, units: [f.units[2].id]),
        ])
    }

    @Test func aRangeReadsAsTheFirstAndLastUnitItReaches() {
        var f = course()
        let m = f.materials[0].id
        pages(&f, 1, 0, 5...8)
        pages(&f, 2, 0, 9...13)
        pages(&f, 3, 0, 14...24)
        #expect(f.sectionLabel(of: m, pages: 7...11) == "König–Hall")
        #expect(f.sectionLabel(of: m, pages: 9...10) == "Hall")
        #expect(f.sectionLabel(of: m, pages: 1...4) == nil)
        #expect(f.units(in: m, meeting: 1...24).map(\.title) == ["König", "Hall", "Augmenting paths"])
    }

    @Test func aClassDrawsItsFirstSplitLecture() {
        var f = course()
        pages(&f, 1, 1, 1...4)
        var session = Session(device: device, at: now, week: 9, date: now)
        session.materials = [SessionMaterial(materialId: f.materials[0].id, firstPage: 1, lastPage: 5),
                             SessionMaterial(materialId: f.materials[1].id),
                             SessionMaterial(materialId: f.materials[1].id, firstPage: 2, lastPage: 6)]
        // The first file has no units' pages, and the second's first link has no range.
        #expect(f.splitProgress(of: session)?.material == f.materials[1].id)
        #expect(f.splitProgress(of: session)?.pages == 2...6)
        pages(&f, 1, 1, 9...12)
        #expect(f.pages(of: f.units[1].id, in: f.materials[1].id) == 1...12)
        #expect(f.pages(of: f.units[2].id, in: f.materials[1].id) == nil)
    }

    @Test func removingAFileLetsGoOfItsPages() throws {
        var f = course()
        pages(&f, 1, 0, 5...8)
        pages(&f, 1, 1, 1...2)
        try f.remove(Material.self, f.materials[0].id)
        #expect(f.units[1].lecturePages.map(\.materialId) == [f.materials[0].id])
    }

    @Test func aBackwardRangeBreaksTheRule() {
        var f = course()
        pages(&f, 1, 0, 5...8)
        f.units[1].lecturePages[0].lastPage = 2
        #expect(CourseFile.model.violations(in: f).contains { $0.rule.name == "Unit.pages" })
    }

    @Test func unitsWithoutPagesKeepTheirJSON() throws {
        let f = course()
        let json = String(decoding: try JSONEncoder().encode(f.units[0]), as: UTF8.self)
        #expect(!json.contains("lectures"))
        var g = f
        pages(&g, 0, 0, 1...4)
        let back = try JSONDecoder().decode(FolioDomain.Unit.self, from: JSONEncoder().encode(g.units[0]))
        #expect(back.lecturePages == g.units[0].lecturePages)
    }

    static let held = zip(Gen.int(in: 0...3), Gen.int(in: 1...25), Gen.int(in: 0...10)).array(of: 0...6)

    /// The zones tile the file from page 1, neighbors differ, and each page lists exactly the units whose pages hold it.
    @Test func zonesTileTheFile() async {
        await propertyCheck(input: Self.held, Gen.int(in: 1...30)) { held, count in
            var f = course()
            let m = f.materials[0].id
            for (u, first, length) in held { pages(&f, u, 0, first...(first + length)) }
            let zones = f.lectureZones(of: m, pageCount: count)
            guard !held.isEmpty else { return #expect(zones.isEmpty) }
            #expect(zones.first?.firstPage == 1 && zones.last?.lastPage == count)
            for (a, b) in zip(zones, zones.dropFirst()) {
                #expect(b.firstPage == a.lastPage + 1)
                #expect(a.units != b.units)
            }
            for zone in zones {
                for page in zone.pages {
                    let holding = f.units.filter { u in u.lecturePages.contains { $0.materialId == m && $0.pages.contains(page) } }.map(\.id)
                    #expect(Set(zone.units) == Set(holding))
                }
            }
        }
    }

    // MARK: Splitting

    @Test func splitReplacesTheFilesPagesAndMakesNewUnits() {
        var f = course()
        let m = f.materials[0].id
        pages(&f, 0, 0, 1...24)
        pages(&f, 0, 1, 1...5)
        let new = UUID()
        f.split(m, into: [
            LectureCut(unit: f.units[1].id, firstPage: 1, lastPage: 8),
            LectureCut(unit: new, title: "Berge", parent: f.units[0].id, firstPage: 9, lastPage: 12),
            LectureCut(unit: new, title: "Berge", firstPage: 20, lastPage: 24),
            LectureCut(unit: UUID(), firstPage: 13, lastPage: 19),
        ], device: device, now: now)
        // The other file's pages stay.
        #expect(f.units[0].lecturePages == [UnitPages(materialId: f.materials[1].id, firstPage: 1, lastPage: 5)])
        #expect(f.units[1].lecturePages == [UnitPages(materialId: m, firstPage: 1, lastPage: 8)])
        let berge = f.units.first { $0.id == new }
        #expect(berge?.title == "Berge" && berge?.parentId == f.units[0].id)
        #expect(berge?.lecturePages.map(\.pages) == [9...12, 20...24])
        // A cut naming no unit and no title makes nothing.
        #expect(f.units.count == 5)
    }

    @Test func aFoundSplitIsTidiedIntoTheFile() throws {
        let s = try #require(LectureSplit([
            .init(title: "Hall", firstPage: 9, lastPage: 9),
            .init(title: "König", firstPage: 5, lastPage: 5),
            .init(title: "Intro", firstPage: 2, lastPage: 2),
            .init(title: "Twice", firstPage: 9, lastPage: 9),
            .init(title: "Past the end", firstPage: 40, lastPage: 40),
        ], pageCount: 24))
        #expect(s.sections.map(\.title) == ["Intro", "König", "Hall", "Twice"])
        #expect(s.sections.map(\.pages) == [1...4, 5...8, 9...9, 10...24])
        #expect(LectureSplit([.init(title: "x", firstPage: 30, lastPage: 30)], pageCount: 24) == nil)
    }

    @Test func boundariesMoveWithinTheirNeighbors() throws {
        var s = try #require(LectureSplit([.init(title: "A", firstPage: 1, lastPage: 1), .init(title: "B", firstPage: 5, lastPage: 5),
                                           .init(title: "C", firstPage: 9, lastPage: 9)], pageCount: 12))
        #expect(s.moveBoundary(after: 0, to: 6) == 6)
        #expect(s.sections.map(\.pages) == [1...6, 7...8, 9...12])
        // Each side keeps a page.
        #expect(s.moveBoundary(after: 0, to: 20) == 7)
        #expect(s.moveBoundary(after: 1, to: 2) == 8)
        #expect(s.boundaryRange(after: 0) == 1...7)
        #expect(s.boundaryRange(after: 2) == nil)
    }

    @Test func splittingAndMergingKeepTheSections() throws {
        var s = LectureSplit(pageCount: 10)
        #expect(s.split(at: 1) == nil)
        #expect(s.split(at: 6, title: "Hall") == 1)
        #expect(s.sections.map(\.pages) == [1...5, 6...10])
        s.setUnit(UUID(), of: 0)
        s.merge(after: 0)
        #expect(s.sections.count == 1 && s.sections[0].pages == 1...10 && s.sections[0].unit != nil)
    }

    @Test func cutsJoinTouchingSectionsOfOneUnitAndSkipTheUnclaimed() throws {
        let unit = UUID()
        var s = try #require(LectureSplit([.init(title: "A", firstPage: 1, lastPage: 1), .init(title: "B", firstPage: 4, lastPage: 4),
                                           .init(title: "C", firstPage: 7, lastPage: 7), .init(title: "", firstPage: 9, lastPage: 9)], pageCount: 10))
        s.setUnit(unit, of: 0)
        s.setUnit(unit, of: 1)
        s.makeNew(2)
        let made = s.sections[2].unit
        s.rename(2, to: "Hall")
        s.makeNew(2)
        #expect(s.sections[2].unit == made)
        // A new unit without a name can't be made.
        s.makeNew(3)
        #expect(s.cuts == [LectureCut(unit: unit, firstPage: 1, lastPage: 6), LectureCut(unit: made!, title: "Hall", firstPage: 7, lastPage: 8)])
        #expect(s.claimed == 3)
    }

    @Test func theCoursesSplitReadsBack() {
        var f = course()
        let m = f.materials[0].id
        pages(&f, 1, 0, 5...8)
        let s = LectureSplit(file: f, material: m, pageCount: 10)
        #expect(s.sections.map(\.pages) == [1...4, 5...8, 9...10])
        #expect(s.sections.map(\.unit) == [nil, f.units[1].id, nil])
        #expect(s.sections[1].title == "König")
        #expect(LectureSplit(file: course(), material: m, pageCount: 10).sections.map(\.pages) == [1...10])
    }

    static let edits = zip(Gen.int(in: 0...2), Gen.int(in: 0...8), Gen.int(in: 1...40)).array(of: 0...12)

    /// Whatever the edits, the sections stay in order, touch, and cover the file.
    @Test func editsKeepTheFileCovered() async {
        await propertyCheck(input: Self.edits, Gen.int(in: 1...30)) { edits, count in
            var s = LectureSplit(pageCount: count)
            for (kind, i, page) in edits {
                switch kind {
                case 0: s.split(at: page)
                case 1: s.moveBoundary(after: i % max(s.sections.count, 1), to: page)
                default: s.merge(after: i % max(s.sections.count, 1))
                }
            }
            #expect(s.sections.first?.firstPage == 1 && s.sections.last?.lastPage == count)
            for (a, b) in zip(s.sections, s.sections.dropFirst()) { #expect(b.firstPage == a.lastPage + 1) }
            #expect(s.sections.allSatisfy { $0.firstPage <= $0.lastPage })
        }
    }

    // MARK: Reading

    @Test func theOutlinesShallowestSplittingLevelIsTheSections() {
        let outline: [LectureReading.Bookmark] = [
            .init(title: "Graph Theory", page: 1, depth: 0),
            .init(title: "1. Matchings", page: 1, depth: 1), .init(title: "König's theorem", page: 5, depth: 1),
            .init(title: "Hall (cont.)", page: 9, depth: 1), .init(title: "Proof", page: 10, depth: 2),
        ]
        let found = LectureReading.sections(outline: outline, pageCount: 24)
        #expect(found?.map(\.title) == ["Matchings", "König's theorem", "Hall"])
        #expect(found?.map(\.firstPage) == [1, 5, 9])
        // A bookmark per slide is no outline.
        let everySlide = (1...20).map { LectureReading.Bookmark(title: "Slide \($0)", page: $0) }
        #expect(LectureReading.sections(outline: everySlide, pageCount: 20) == nil)
        #expect(LectureReading.sections(outline: [.init(title: "Only", page: 1)], pageCount: 20) == nil)
    }

    @Test func slideTitlesSplitAtUnitNamesAndDividers() {
        func page(_ t: String?, _ words: Int = 40) -> LectureReading.Page { .init(title: t, words: words) }
        let pages = [page("Matchings"), page("Matchings (cont.)"), page("Definitions"), page("Examples"),
                     page("König's theorem", 3), page("Proof"), page("Proof (2)"), page("Exercise"),
                     page("Hall"), page("Proof"), page("Corollaries"), page(nil)]
        let found = LectureReading.sections(pages: pages, units: ["Hall의 결혼 정리", "Hall"])
        #expect(found?.map(\.title) == ["Matchings", "König's theorem", "Hall"])
        #expect(found?.map(\.firstPage) == [1, 5, 9])
        // Every slide its own title and nothing to tell chapters by: left to Claude.
        #expect(LectureReading.sections(pages: (1...12).map { page("Slide \($0)") }, units: []) == nil)
    }

    @Test func titlesLoseTheDecksNumbering() {
        #expect(LectureReading.clean("Part 2: Hall's theorem (cont.)") == "Hall's theorem")
        #expect(LectureReading.clean("3.2 Augmenting paths") == "Augmenting paths")
        #expect(LectureReading.clean("Lecture 6 – Flows") == "Flows")
        #expect(LectureReading.clean("  Menger  계속 ") == "Menger")
    }

    @Test func foundTitlesMatchUnitsByName() {
        let units = ["매칭", "König", "Hall의 결혼 정리", "Augmenting paths", "AB"]
        #expect(SectionMatch.unit(for: "König", in: units) == 1)
        #expect(SectionMatch.unit(for: "konig", in: ["konig"]) == 0)
        #expect(SectionMatch.unit(for: "3. augmenting  paths", in: units) == 3)
        #expect(SectionMatch.unit(for: "Hall", in: units) == 2)
        #expect(SectionMatch.unit(for: "Berge", in: units) == nil)
        // Two letters match only exactly.
        #expect(SectionMatch.unit(for: "ABC", in: units) == nil)
    }

    @Test func aFoundSplitTakesUnitsByNameOrProposesNewOnes() throws {
        let f = course()
        let found = try #require(LectureSplit([.init(title: "Matching", firstPage: 1, lastPage: 1), .init(title: "König", firstPage: 5, lastPage: 5),
                                               .init(title: "Berge", firstPage: 14, lastPage: 14)], pageCount: 24))
        let s = SectionMatch.match(found, units: f.units)
        #expect(s.sections[1].unit == f.units[1].id && s.sections[1].match == .name)
        #expect(s.sections[2].isNew && s.sections[2].unit != nil)
        #expect(s.cuts.last == LectureCut(unit: s.sections[2].unit!, title: "Berge", firstPage: 14, lastPage: 24))
    }
}
