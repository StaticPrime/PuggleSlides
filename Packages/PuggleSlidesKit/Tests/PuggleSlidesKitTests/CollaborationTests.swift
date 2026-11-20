import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PuggleSlidesKit

/// A seeded random number generator, so a failing run can be repeated.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var value = state
        value ^= value >> 33
        value = value &* 0xFF51_AFD7_ED55_8CCD
        value ^= value >> 33
        return value
    }
}

/// One simulated Mac with a shared presentation: its parts, what they show, and its side of the log.
private final class SimulatedMac {
    let name: String
    var state: PresentationState
    var shown: Presentation
    let client: SyncClient<PresentationChange>
    /// Log revisions this Mac has been handed.
    var delivered = 0

    init(_ name: String, snapshot: SyncSnapshot) {
        self.name = name
        state = snapshot.state
        shown = snapshot.state.presentation()
        client = SyncClient(revision: snapshot.revision, author: name, authorName: name)
    }

    /// An edit made here, as the app records one: the change between what showed and what the edit made.
    func edit(_ body: (inout Presentation) -> Void) {
        var edited = shown
        body(&edited)
        let change = state.change(from: shown, to: edited)
        guard !change.isEmpty else { return }
        state.apply(change)
        shown = state.presentation()
        client.local(change)
    }

    func apply(_ changes: [PresentationChange]) {
        for change in changes { state.apply(change) }
        shown = state.presentation()
    }
}

/// The log: one change per revision, taken by whoever claims the revision first.
private final class SimulatedLog {
    var changes: [LoggedChange<PresentationChange>] = []

    /// Sends a Mac's next change; another change already at its revision means it's sent again after catching up.
    func send(from mac: SimulatedMac) {
        guard let next = mac.client.nextToSend() else { return }
        if next.revision == changes.count + 1 {
            changes.append(next)
            mac.client.sent(next.id)
        } else {
            mac.apply(mac.client.sendTaken(next.id, by: changes[next.revision - 1]))
        }
    }

    /// Hands a Mac up to `count` changes it hasn't had, in a jumbled order.
    func deliver(to mac: SimulatedMac, count: Int, using random: inout SeededRandom) {
        let end = min(changes.count, mac.delivered + count)
        guard end > mac.delivered else { return }
        let batch = Array(changes[mac.delivered..<end]).shuffled(using: &random)
        mac.delivered = end
        mac.apply(mac.client.receive(batch))
    }
}

private func textBox(_ text: String, x: Double, y: Double) -> SlideElement {
    SlideElement(name: "Text box", placement: Placement(frame: SlideRect(x: x, y: y, width: 200, height: 40)),
                 content: .shape(Shape(text: TextBody(text), isTextBox: true)))
}

/// A small deck to share: three slides, each with a title and a text box.
private func sampleDeck() -> Presentation {
    var presentation = Presentation.makeDefault()
    let layout = presentation.themes[0].layout(kind: .titleAndBody)!.id
    presentation.slides = (1...3).map { number in
        var slide = presentation.makeSlide(layoutID: layout)
        slide.elements.append(textBox("Slide \(number) notes", x: 40, y: 300))
        slide.notes = TextBody("Speaker notes \(number)")
        return slide
    }
    presentation.slides[0].comments = [CommentThread(comments: [Comment(author: "Ana", text: "Nice")])]
    return presentation
}

private func withoutComments(_ presentation: Presentation) -> Presentation {
    var presentation = presentation
    for index in presentation.slides.indices { presentation.slides[index].comments = [] }
    return presentation
}

@Suite struct OrderKeyTests {
    @Test func keysBetweenAnyTwoKeysSortBetweenThem() {
        var random = SeededRandom(1)
        var keys = OrderKeys.spread(5)
        #expect(keys == keys.sorted())
        for _ in 0..<2_000 {
            let index = Int.random(in: 0...keys.count, using: &random)
            let lower = index > 0 ? keys[index - 1] : nil
            let upper = index < keys.count ? keys[index] : nil
            let key = OrderKeys.between(lower, upper)
            if let lower { #expect(lower < key) }
            if let upper { #expect(key < upper) }
            #expect(key.last != "0")
            keys.insert(key, at: index)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
        // Inserting again and again at one place still makes short keys.
        #expect(keys.map(\.count).max()! < 40)
    }

    @Test func manyKeysInOneGapStayShort() {
        let keys = OrderKeys.keys(500, between: "a", "b")
        #expect(keys == keys.sorted())
        #expect(keys.allSatisfy { "a" < $0 && $0 < "b" })
        #expect(keys.map(\.count).max()! <= 4)
    }

    @Test func assignedKeysSortIntoTheNewOrder() {
        var random = SeededRandom(2)
        for _ in 0..<300 {
            let count = Int.random(in: 0...12, using: &random)
            var ids = (0..<count).map { _ in UUID() }
            var keys = Dictionary(uniqueKeysWithValues: zip(ids, OrderKeys.spread(count)))
            // Some keys the same, as when two Macs add items in one place at the same time.
            if count > 2, Bool.random(using: &random) { keys[ids[1]] = keys[ids[0]] }
            ids.sort { (keys[$0]!, $0.uuidString) < (keys[$1]!, $1.uuidString) }
            var order = ids.shuffled(using: &random)
            if Bool.random(using: &random) { order.insert(UUID(), at: Int.random(in: 0...order.count, using: &random)) }
            if !order.isEmpty, Bool.random(using: &random) { order.remove(at: Int.random(in: 0..<order.count, using: &random)) }
            let kept = Set(order)
            let assigned = OrderKeys.assign(order, keys: keys.filter { kept.contains($0.key) }, tieBreak: { $0.uuidString })
            let all = order.map { (id: $0, key: assigned[$0] ?? keys[$0]!) }
            #expect(OrderKeys.sorted(all, tieBreak: { $0.uuidString }) == order)
        }
    }

    @Test func movingOneItemGivesOnlyItANewKey() {
        let ids = (0..<8).map { _ in UUID() }
        let keys = Dictionary(uniqueKeysWithValues: zip(ids, OrderKeys.spread(8)))
        var order = ids
        order.insert(order.remove(at: 6), at: 1)
        let assigned = OrderKeys.assign(order, keys: keys, tieBreak: { $0.uuidString })
        #expect(Array(assigned.keys) == [ids[6]])
    }
}

@Suite struct SharedPresentationTests {
    @Test func partsDescribeThePresentationExactly() {
        let deck = sampleDeck()
        let state = PresentationState(deck)
        #expect(state.presentation() == withoutComments(deck))
        // Every object is three parts at most, and a slide's own parts only where it has something.
        let elementParts = state.parts.keys.filter { if case .element = $0 { true } else { false } }
        #expect(elementParts.count <= deck.slides.reduce(0) { $0 + $1.elements.count * 3 })
    }

    @Test func anEditChangesOnlyThePartsItTouched() throws {
        let deck = sampleDeck()
        let state = PresentationState(deck)
        let shown = state.presentation()
        var edited = shown
        edited.slides[1].elements[2].placement?.frame.x += 30
        let moved = state.change(from: shown, to: edited)
        let slide = shown.slides[1].id, element = shown.slides[1].elements[2].id
        #expect(Array(moved.parts.keys) == [.element(slide: slide, element: element, part: .placement)])

        edited = shown
        edited.slides[1].elements[2].shape?.text = TextBody("Rewritten")
        #expect(Array(state.change(from: shown, to: edited).parts.keys) == [.element(slide: slide, element: element, part: .text)])

        edited = shown
        edited.slides[1].elements[2].shape?.fill = .solid(ColorRef(RGBColor(red: 200, green: 0, blue: 0)))
        #expect(Array(state.change(from: shown, to: edited).parts.keys) == [.element(slide: slide, element: element, part: .body)])

        edited = shown
        edited.slides.swapAt(0, 2)
        let reordered = state.change(from: shown, to: edited)
        #expect(reordered.parts.keys.allSatisfy { if case .slideOrder = $0 { true } else { false } })
        #expect(reordered.parts.count <= 2)

        // Comments aren't parts.
        edited = shown
        edited.slides[0].comments.append(CommentThread(comments: [Comment(author: "Ben", text: "Hi")]))
        #expect(state.change(from: shown, to: edited).isEmpty)
    }

    @Test func deletingASlideRemovesAllItsParts() {
        let deck = sampleDeck()
        var state = PresentationState(deck)
        let shown = state.presentation()
        var edited = shown
        let gone = edited.slides.remove(at: 1)
        state.apply(state.change(from: shown, to: edited))
        #expect(!state.parts.keys.contains { $0.slideID == gone.id })
        #expect(state.presentation() == edited)
    }

    @Test func changesAndSnapshotsSurviveEncoding() throws {
        let deck = sampleDeck()
        var state = PresentationState(deck)
        var edited = state.presentation()
        edited.media["picture"] = MediaItem(data: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), contentType: "image/png")
        edited.slides[0].background = .solid(ColorRef(RGBColor(red: 1, green: 2, blue: 3)))
        edited.slides[2].elements.removeLast()
        let change = state.change(from: state.presentation(), to: edited)
        #expect(try PresentationChange(encoded: change.encoded) == change)
        state.apply(change)
        let snapshot = SyncSnapshot(revision: 12, state: state)
        let decoded = try SyncSnapshot(encoded: snapshot.encoded)
        #expect(decoded.revision == 12)
        #expect(decoded.state == state)
        #expect(decoded.state.presentation() == edited)
    }

    @Test func concurrentEditsToDifferentThingsAllSurvive() {
        let snapshot = SyncSnapshot(revision: 0, state: PresentationState(sampleDeck()))
        let log = SimulatedLog()
        let ana = SimulatedMac("ana", snapshot: snapshot), ben = SimulatedMac("ben", snapshot: snapshot)
        var random = SeededRandom(3)
        // Same slide, different objects; the same object, its place and its text; a slide added on each Mac.
        ana.edit { $0.slides[0].elements[2].placement?.frame.y = 111 }
        ben.edit { $0.slides[0].elements[0].shape?.text = TextBody("Ben’s title") }
        ana.edit { $0.slides[1].elements[2].placement?.frame.x = 222 }
        ben.edit { $0.slides[1].elements[2].shape?.text = TextBody("Ben typed here") }
        ana.edit { $0.slides.append($0.makeSlide(layoutID: $0.themes[0].layouts[0].id)) }
        ben.edit { $0.slides.insert($0.makeSlide(layoutID: $0.themes[0].layouts[1].id), at: 3) }
        for _ in 0..<20 {
            log.send(from: ana)
            log.send(from: ben)
            log.deliver(to: ana, count: 10, using: &random)
            log.deliver(to: ben, count: 10, using: &random)
        }
        #expect(!ana.client.hasPending && !ben.client.hasPending)
        #expect(ana.shown == ben.shown)
        let result = ana.shown
        #expect(result.slides.count == 5)
        #expect(result.slides[0].elements[2].placement?.frame.y == 111)
        #expect(result.slides[0].elements[0].shape?.text?.plainText == "Ben’s title")
        #expect(result.slides[1].elements[2].placement?.frame.x == 222)
        #expect(result.slides[1].elements[2].shape?.text?.plainText == "Ben typed here")
    }

    @Test func theSameThingChangedAtOnceEndsAsTheLaterChangeInTheLog() {
        let snapshot = SyncSnapshot(revision: 0, state: PresentationState(sampleDeck()))
        let log = SimulatedLog()
        let ana = SimulatedMac("ana", snapshot: snapshot), ben = SimulatedMac("ben", snapshot: snapshot)
        var random = SeededRandom(4)
        ana.edit { $0.slides[2].elements[2].shape?.text = TextBody("Ana’s words") }
        ben.edit { $0.slides[2].elements[2].shape?.text = TextBody("Ben’s words") }
        log.send(from: ana)
        log.send(from: ben)
        for _ in 0..<5 {
            log.send(from: ben)
            log.deliver(to: ana, count: 5, using: &random)
            log.deliver(to: ben, count: 5, using: &random)
        }
        #expect(ana.shown == ben.shown)
        #expect(ana.shown.slides[2].elements[2].shape?.text?.plainText == "Ben’s words")
    }

    /// Several Macs make random edits at the same time (slides and objects added, moved, deleted, restyled, typed in)
    /// and send them through the log, hearing of each other's in jumbled order; they always end the same.
    @Test(arguments: [11, 12, 13, 14, 15, 16])
    func randomConcurrentEditsEndTheSameEverywhere(seed: Int) {
        var random = SeededRandom(UInt64(seed))
        let initial = SyncSnapshot(revision: 0, state: PresentationState(sampleDeck()))
        let log = SimulatedLog()
        let macs = ["ana", "ben", "cy"].map { SimulatedMac($0, snapshot: initial) }
        for _ in 0..<400 {
            let mac = macs.randomElement(using: &random)!
            switch Int.random(in: 0..<10, using: &random) {
            case 0..<5: mac.edit { randomEdit(&$0, using: &random) }
            case 5..<8: log.send(from: mac)
            default: log.deliver(to: mac, count: Int.random(in: 1...6, using: &random), using: &random)
            }
        }
        // Everyone sends what's left and hears everything.
        var rounds = 0
        while macs.contains(where: { $0.client.hasPending || $0.delivered < log.changes.count }), rounds < 500 {
            for mac in macs {
                log.send(from: mac)
                log.deliver(to: mac, count: 50, using: &random)
            }
            rounds += 1
        }
        var replayed = initial.state
        for logged in log.changes { replayed.apply(logged.change) }
        for mac in macs {
            #expect(mac.state == replayed, "\(mac.name)'s parts differ")
            #expect(mac.shown == replayed.presentation(), "\(mac.name)'s presentation differs")
        }
        #expect(log.changes.count > 50)
    }

    private func randomEdit(_ presentation: inout Presentation, using random: inout SeededRandom) {
        let layouts = presentation.themes[0].layouts.map(\.id)
        func anySlide() -> Int? { presentation.slides.isEmpty ? nil : Int.random(in: 0..<presentation.slides.count, using: &random) }
        switch Int.random(in: 0..<12, using: &random) {
        case 0:
            var slide = presentation.makeSlide(layoutID: layouts.randomElement(using: &random)!)
            slide.elements.append(textBox("New", x: 10, y: 10))
            presentation.slides.insert(slide, at: Int.random(in: 0...presentation.slides.count, using: &random))
        case 1:
            if presentation.slides.count > 1, let index = anySlide() { presentation.slides.remove(at: index) }
        case 2:
            if let from = anySlide() {
                let slide = presentation.slides.remove(at: from)
                presentation.slides.insert(slide, at: Int.random(in: 0...presentation.slides.count, using: &random))
            }
        case 3:
            if let index = anySlide() {
                let count = presentation.slides[index].elements.count
                presentation.slides[index].elements.insert(textBox("Box \(Int.random(in: 0..<999, using: &random))", x: 5, y: 5),
                                                           at: Int.random(in: 0...count, using: &random))
            }
        case 4:
            if let index = anySlide(), !presentation.slides[index].elements.isEmpty {
                presentation.slides[index].elements.remove(at: Int.random(in: 0..<presentation.slides[index].elements.count, using: &random))
            }
        case 5, 6:
            if let index = anySlide(), !presentation.slides[index].elements.isEmpty {
                let element = Int.random(in: 0..<presentation.slides[index].elements.count, using: &random)
                presentation.slides[index].elements[element].placement = Placement(frame: SlideRect(x: Double(Int.random(in: 0..<500, using: &random)), y: 20,
                                                                                                     width: 100, height: 50))
            }
        case 7:
            if let index = anySlide(), let element = presentation.slides[index].elements.indices.randomElement(using: &random),
               presentation.slides[index].elements[element].shape != nil {
                presentation.slides[index].elements[element].shape?.text = TextBody("Typed \(Int.random(in: 0..<999, using: &random))")
            }
        case 8:
            if let index = anySlide(), let element = presentation.slides[index].elements.indices.randomElement(using: &random),
               presentation.slides[index].elements[element].shape != nil {
                let value = UInt8.random(in: 0...255, using: &random)
                presentation.slides[index].elements[element].shape?.fill = .solid(ColorRef(RGBColor(red: value, green: 10, blue: 20)))
            }
        case 9:
            if let index = anySlide(), presentation.slides[index].elements.count > 1 {
                let count = presentation.slides[index].elements.count
                let element = presentation.slides[index].elements.remove(at: Int.random(in: 0..<count, using: &random))
                presentation.slides[index].elements.insert(element, at: Int.random(in: 0..<count, using: &random))
            }
        case 10:
            if let index = anySlide() {
                presentation.slides[index].notes = TextBody("Notes \(Int.random(in: 0..<999, using: &random))")
                presentation.slides[index].isSkipped.toggle()
            }
        default:
            presentation.themes[0].name = "Theme \(Int.random(in: 0..<99, using: &random))"
            if let index = anySlide() {
                presentation.slides[index].background = .solid(ColorRef(RGBColor(red: 9, green: UInt8.random(in: 0...255, using: &random), blue: 9)))
            }
        }
    }
}

@Suite struct GapTests {
    @Test func aChangeThatDidNotComeIsMissedUntilItDoes() {
        let snapshot = SyncSnapshot(revision: 0, state: PresentationState(sampleDeck()))
        let log = SimulatedLog()
        let ana = SimulatedMac("ana", snapshot: snapshot), ben = SimulatedMac("ben", snapshot: snapshot)
        for word in ["one", "two", "three"] {
            ana.edit { $0.slides[0].elements[2].shape?.text = TextBody(word) }
            log.send(from: ana)
        }
        // The second change doesn't come with the others: nothing after it can be applied, and it's the one asked for.
        ben.apply(ben.client.receive([log.changes[0], log.changes[2]]))
        #expect(ben.shown.slides[0].elements[2].shape?.text?.plainText == "one")
        #expect(ben.client.isMissingChanges)
        #expect(ben.client.missingRevisions == 2...2)
        ben.apply(ben.client.receive([log.changes[1]]))
        #expect(ben.shown == ana.shown)
        #expect(!ben.client.isMissingChanges && ben.client.missingRevisions == nil)
    }

    @Test func startingOverDropsWhatWasWaitingToGo() {
        let mac = SimulatedMac("ana", snapshot: SyncSnapshot(revision: 0, state: PresentationState(sampleDeck())))
        mac.edit { $0.slides[0].elements[2].shape?.text = TextBody("d") }
        mac.edit { $0.slides[0].elements[2].shape?.text = TextBody("de") }
        #expect(mac.client.hasPending)
        mac.client.discardPending()
        #expect(!mac.client.hasPending && mac.client.nextToSend() == nil)
    }
}

@Suite struct StorablePictureTests {
    private func picture(_ type: UTType) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test(arguments: [UTType.tiff, UTType.bmp])
    func picturesThatComeAsTIFFOrBMPAreKeptAsPNG(type: UTType) throws {
        let original = try picture(type)
        let stored = try #require(MediaItem.storable(original))
        #expect(stored.contentType == "image/png" && MediaItem.contentType(sniffing: stored.data) == "image/png")
        #expect(stored.data.count < original.count)
        // Same pixels, and the same resolution, so it shows at the same size.
        let source = try #require(CGImageSourceCreateWithData(stored.data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 60 && properties[kCGImagePropertyPixelHeight] as? Int == 40)
        #expect((properties[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 144) < 1 } == true)
    }

    @Test func otherPicturesAreKeptAsTheyAre() throws {
        let png = try picture(.png)
        #expect(MediaItem.storable(png)?.data == png)
        #expect(MediaItem.storable(Data("not a picture".utf8)) == nil)
    }
}

@Suite struct SharedCommentTests {
    @Test func repliesFromBothSidesAndLocalChangesMerge() {
        let start = CommentThread(comments: [Comment(author: "Alex", date: Date(timeIntervalSince1970: 0), text: "Bigger title?")])
        var local = start
        local.comments.append(Comment(author: "Alex", date: Date(timeIntervalSince1970: 20), text: "Or bolder"))
        local.isResolved = true
        var server = start
        server.comments.append(Comment(author: "Ana", date: Date(timeIntervalSince1970: 10), text: "Agreed"))
        let merged = SharedComment.merge(local: local, base: start, server: server)
        #expect(merged.comments.map(\.text) == ["Bigger title?", "Agreed", "Or bolder"])
        #expect(merged.isResolved)
        // A reply deleted here goes, even though the server still has it.
        var deleting = merged
        deleting.comments.removeAll { $0.text == "Agreed" }
        #expect(SharedComment.merge(local: deleting, base: merged, server: merged).comments.map(\.text) == ["Bigger title?", "Or bolder"])
    }

    @Test func sharedCommentsRoundTripWithTheirAuthor() throws {
        let thread = CommentThread(comments: [Comment(author: "Ana Lopez", authorID: "ana@example.com", text: "Hello")], elementID: UUID())
        let shared = SharedComment(thread: thread, slideID: UUID())
        let decoded = try #require(CollaborationRecords.decode(SharedComment.self, from: CollaborationRecords.encode(shared)))
        #expect(decoded == shared)
        #expect(decoded.thread.comments[0].authorID == "ana@example.com")
    }
}

@Suite struct ChangeTallyTests {
    @Test func aRunOfEditsBecomesOneShortSummary() {
        let deck = sampleDeck()
        var state = PresentationState(deck)
        var tally = ChangeTally()
        var shown = state.presentation()
        func edit(_ body: (inout Presentation) -> Void) {
            var edited = shown
            body(&edited)
            let change = state.change(from: shown, to: edited)
            tally.record(change, before: shown)
            state.apply(change)
            shown = state.presentation()
        }
        edit { $0.slides.append($0.makeSlide(layoutID: $0.themes[0].layouts[0].id)) }
        edit { $0.slides[0].elements[2].shape?.text = TextBody("Changed") }
        edit { $0.slides[1].elements[2].placement?.frame.x = 5 }
        edit { $0.slides[1].elements.append(SlideElement(placement: nil, content: .picture(Picture(mediaID: "m")))) }
        tally.recordComment("Looks good to me")
        let notice = tally.notice(author: "Ana Lopez", documentTitle: "Plan")
        #expect(notice?.title == "Ana Lopez edited “Plan”")
        #expect(notice?.body == "Added a slide, edited 2 slides, added an image and added a comment.")
    }

    @Test func aSlideAddedThenDeletedIsNothing() {
        var state = PresentationState(sampleDeck())
        var tally = ChangeTally()
        var shown = state.presentation()
        for step in 0..<2 {
            var edited = shown
            if step == 0 { edited.slides.append(edited.makeSlide(layoutID: edited.themes[0].layouts[0].id)) } else { edited.slides.removeLast() }
            let change = state.change(from: shown, to: edited)
            tally.record(change, before: shown)
            state.apply(change)
            shown = state.presentation()
        }
        #expect(tally.notice(author: "Ana", documentTitle: "Plan") == nil)
    }

    @Test func commentsAloneSayWhatWasSaid() {
        var tally = ChangeTally()
        tally.recordReply("Thanks, will do")
        #expect(tally.notice(author: "Ben", documentTitle: "Plan")?.title == "Ben replied in “Plan”")
        #expect(tally.notice(author: "Ben", documentTitle: "Plan")?.body == "“Thanks, will do”")
    }
}
