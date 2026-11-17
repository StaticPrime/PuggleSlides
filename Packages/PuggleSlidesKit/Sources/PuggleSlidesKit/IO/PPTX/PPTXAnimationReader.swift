import Foundation

/// Reads a slide's timing tree into PuggleSlides' animations. Effects map to the nearest one of the same kind
/// (an entrance to an entrance, an exit to an exit); paragraph-by-paragraph builds become one animation.
/// What can't be represented (motion paths, emphasis other than spin, triggers, sounds) is dropped and noted.
///
/// Clips' timing is read too: a play command in the main sequence plays a clip as the slide appears when no click comes
/// before it, and on a click otherwise; a sequence a clip's own click triggers, which plays and pauses it, is how
/// PowerPoint plays a clip only when it's clicked. Each clip's media node holds its other settings.
struct PPTXAnimationReader {
    struct Result {
        var animations: [SlideAnimation] = []
        var hasUnsupported = false
        /// How clips with a play command in the main sequence start, by element id.
        var playback: [UUID: MediaPlayback] = [:]
        /// Each clip's `p:cMediaNode`, by element id.
        var mediaNodes: [UUID: XNode] = [:]
    }

    /// One effect node, as found.
    private struct Effect {
        var effect: AnimationEffect
        var start: AnimationStart
        var spid: String
        var groupID: String?
        var preset: String
        var paragraphs: ClosedRange<Int>?
        var delay: Double
        var duration: Double?
        /// A media command: it plays `clip`, or something that isn't kept.
        var isMedia = false
        var clip: UUID?
    }

    static let behaviorNames: Set<String> = ["set", "anim", "animEffect", "animRot", "animScale", "animMotion", "animClr", "cmd", "audio", "video"]
    static let maxDepth = 24

    private let elements: [String: SlideElement]
    private let clips: [String: UUID]
    private var result = Result()

    /// `elements` are the slide's own elements, and `clips` the element ids of its clips at any depth, by `cNvPr` id.
    static func read(_ root: XNode, elements: [String: SlideElement], clips: [String: UUID] = [:]) -> Result {
        guard let timing = timingNode(root) else { return Result() }
        var reader = PPTXAnimationReader(elements: elements, clips: clips)
        reader.read(timing)
        return reader.result
    }

    /// Whether a layout's or master's timing animates anything (which slides can't keep).
    static func animates(_ root: XNode) -> Bool {
        guard let timing = timingNode(root) else { return false }
        return timing.descendants("cTn").contains { $0["presetClass"] != nil || $0["nodeType"]?.hasSuffix("Effect") == true }
    }

    private init(elements: [String: SlideElement], clips: [String: UUID]) {
        self.elements = elements
        self.clips = clips
    }

    /// `p:timing` itself, or the one in an `mc:AlternateContent`.
    private static func timingNode(_ root: XNode) -> XNode? {
        for child in root.children {
            if child.name == "timing" { return child }
            guard child.name == "AlternateContent" else { continue }
            for branch in child.children("Choice") + child.children("Fallback") {
                if let timing = branch.child("timing") { return timing }
            }
        }
        return nil
    }

    private mutating func read(_ timing: XNode) {
        guard let root = timing.child("tnLst")?.children.first?.child("cTn") else { return }
        if !clips.isEmpty {
            for node in timing.descendants("video") + timing.descendants("audio") {
                guard let media = node.child("cMediaNode"), let spid = media.child("tgtEl")?.child("spTgt")?["spid"], let clip = clips[spid],
                      result.mediaNodes[clip] == nil else { continue }
                result.mediaNodes[clip] = media
            }
        }
        var sequences = (root.child("childTnLst")?.children("seq") ?? []).compactMap { $0.child("cTn") }
        // Sequences that start when a shape is clicked (triggers) can't be kept, except a clip's own, which plays it.
        for sequence in sequences where sequence["nodeType"] == "interactiveSeq" && !isMediaTrigger(sequence) {
            result.hasUnsupported = true
        }
        sequences.removeAll { $0["nodeType"] == "interactiveSeq" }
        guard let main = sequences.first(where: { $0["nodeType"] == "mainSeq" }) ?? sequences.first else { return }

        var effects: [Effect] = []
        for group in main.child("childTnLst")?.children ?? [] {
            guard let node = group.child("cTn") else { continue }
            if Self.isEffect(node) {
                // An effect straight in the sequence: it starts on a click.
                if let effect = effect(node, defaultStart: .onClick) { effects.append(effect) }
                continue
            }
            let startsWithSlide = (node.child("stCondLst")?.children("cond") ?? []).contains { $0["evt"] == "onBegin" }
            var first = true
            collect(node, depth: 0, into: &effects) { isFirstInStep in
                defer { first = false }
                if first { return startsWithSlide ? .withPrevious : .onClick }
                return isFirstInStep ? .afterPrevious : .withPrevious
            }
        }
        result.animations = merged(withoutMedia(effects))
    }

    /// The effects without media commands, noting how each clip played by one starts: as the slide appears when no click
    /// comes before its command, else on a click. An effect that ran with or after a click-started command takes its
    /// click, so the effects after it still need as many clicks.
    private mutating func withoutMedia(_ effects: [Effect]) -> [Effect] {
        var kept: [Effect] = []
        var clicked = false
        var pendingClick = false
        for var effect in effects {
            if effect.start == .onClick { clicked = true }
            guard !effect.isMedia else {
                if let clip = effect.clip, result.playback[clip] == nil { result.playback[clip] = clicked ? .onClick : .automatically }
                if effect.start == .onClick { pendingClick = true }
                continue
            }
            if pendingClick { effect.start = .onClick }
            pendingClick = false
            kept.append(effect)
        }
        return kept
    }

    /// Whether a triggered sequence is a clip's own: its click starts it, and all it does is play or pause the clip.
    private func isMediaTrigger(_ sequence: XNode) -> Bool {
        let conditions = sequence.child("stCondLst")?.children("cond") ?? []
        guard let spid = conditions.lazy.compactMap({ $0["evt"] == "onClick" ? $0.child("tgtEl")?.child("spTgt")?["spid"] : nil }).first,
              clips[spid] != nil else { return false }
        let behaviors = Self.behaviorNames.flatMap { sequence.descendants($0) }
        return behaviors.contains(where: PPTXMedia.isPlayCommand)
            && behaviors.allSatisfy { behavior in
                guard PPTXMedia.targetShape(behavior) == spid else { return false }
                return behavior.name == "video" || behavior.name == "audio" || (behavior.name == "cmd" && (behavior["type"] ?? "call") == "call")
            }
    }

    private static func isEffect(_ node: XNode) -> Bool {
        if node["presetClass"] != nil { return true }
        if let type = node["nodeType"], ["clickEffect", "withEffect", "afterEffect"].contains(type) { return true }
        return node.child("childTnLst")?.children.contains { behaviorNames.contains($0.name) } ?? false
    }

    /// The effects below a click group, in order. Each nested group is an "after previous" step.
    private mutating func collect(_ node: XNode, depth: Int, into effects: inout [Effect], defaultStart: (Bool) -> AnimationStart) {
        guard depth < Self.maxDepth else {
            result.hasUnsupported = true
            return
        }
        var firstInStep = true
        for child in node.child("childTnLst")?.children ?? [] {
            guard let timeNode = child.child("cTn") else { continue }
            if Self.isEffect(timeNode) {
                if let effect = effect(timeNode, defaultStart: defaultStart(firstInStep)) { effects.append(effect) }
                firstInStep = false
            } else {
                collect(timeNode, depth: depth + 1, into: &effects, defaultStart: defaultStart)
            }
        }
    }

    // MARK: Effects

    private mutating func effect(_ node: XNode, defaultStart: AnimationStart) -> Effect? {
        let start: AnimationStart = switch node["nodeType"] {
        case "clickEffect": .onClick
        case "withEffect": .withPrevious
        case "afterEffect": .afterPrevious
        default: defaultStart
        }
        let behaviors = node.child("childTnLst")?.children.filter { Self.behaviorNames.contains($0.name) } ?? []
        var presetClass = node["presetClass"] ?? Self.inferredClass(behaviors)
        let mediaOnly = !behaviors.isEmpty && behaviors.allSatisfy {
            $0.name == "video" || $0.name == "audio" || ($0.name == "cmd" && ($0["type"] ?? "call") == "call")
        }
        if presetClass == "mediacall" || (node["presetClass"] == nil && mediaOnly) {
            return mediaEffect(behaviors, start: start)
        }
        // Sounds and after-effects (dimming) ride along in a sub-list.
        if node.child("subTnLst").map({ !$0.children.isEmpty }) ?? false { result.hasUnsupported = true }

        // The target: a top-level element, maybe some of its paragraphs.
        guard let target = behaviors.lazy.compactMap({ $0.child("cBhvr")?.child("tgtEl")?.child("spTgt") }).first,
              let spid = target["spid"], elements[spid] != nil else {
            result.hasUnsupported = true
            return nil
        }
        var paragraphs: ClosedRange<Int>?
        if let range = target.child("txEl")?.child("pRg"), let first = PPTXValue.int(range["st"]), let last = PPTXValue.int(range["end"]) {
            let low = min(max(first, 0), 100_000), high = min(max(last, 0), 100_000)
            paragraphs = min(low, high)...max(low, high)
        } else if target.child("txEl") != nil || target.children.contains(where: { $0.name != "txEl" }) {
            // Letters, sub-shapes and chart parts can't be targeted on their own.
            result.hasUnsupported = true
        }

        if presetClass.isEmpty { presetClass = "entr" }
        let id = PPTXValue.int(node["presetID"])
        let subtype = PPTXValue.int(node["presetSubtype"]) ?? 0
        guard let effect = Self.effect(presetClass: presetClass, id: id, subtype: subtype, behaviors: behaviors) else {
            result.hasUnsupported = true
            return nil
        }
        let delay = (node.child("stCondLst")?.children("cond").lazy.compactMap { PPTXValue.double($0["delay"]) }.first) ?? 0
        return Effect(effect: effect, start: start, spid: spid, groupID: node["grpId"], preset: "\(presetClass) \(id ?? -1) \(subtype)",
                      paragraphs: paragraphs, delay: min(max(delay, 0), 86_400_000) / 1000, duration: Self.length(behaviors))
    }

    /// A media command. One that plays a clip notes it; others on a clip, pausing or stopping it, can't be kept; those on
    /// media that wasn't kept go with it, which already says so.
    private mutating func mediaEffect(_ behaviors: [XNode], start: AnimationStart) -> Effect {
        var effect = Effect(effect: .appear, start: start, spid: "", preset: "media", delay: 0, isMedia: true)
        guard let spid = behaviors.lazy.compactMap(PPTXMedia.targetShape).first, let clip = clips[spid] else { return effect }
        let commands = behaviors.filter { $0.name == "cmd" }
        if commands.contains(where: PPTXMedia.isPlayCommand) {
            effect.clip = clip
        } else if !commands.isEmpty {
            result.hasUnsupported = true
        }
        return effect
    }

    /// How long an effect runs: the latest end of its behaviors, in seconds.
    private static func length(_ behaviors: [XNode]) -> Double? {
        var longest: Double?
        for behavior in behaviors {
            guard let timeNode = behavior.child("cBhvr")?.child("cTn"), let duration = PPTXValue.double(timeNode["dur"]) else { continue }
            let delay = (timeNode.child("stCondLst")?.children("cond").lazy.compactMap { PPTXValue.double($0["delay"]) }.first) ?? 0
            let end = max(0, delay) + max(0, duration)
            longest = max(longest ?? 0, end)
        }
        return longest.map { min($0, 86_400_000) / 1000 }
    }

    /// Effects without a preset class: an entrance shows its element, an exit hides it, a turn is an emphasis.
    private static func inferredClass(_ behaviors: [XNode]) -> String {
        if behaviors.contains(where: { $0.name == "animMotion" }) { return "path" }
        for behavior in behaviors where behavior.name == "set" {
            switch behavior.child("to")?.child("strVal")?["val"] {
            case "visible": return "entr"
            case "hidden": return "exit"
            default: continue
            }
        }
        if let effect = behaviors.first(where: { $0.name == "animEffect" }) { return effect["transition"] == "out" ? "exit" : "entr" }
        if behaviors.contains(where: { $0.name == "animRot" }) { return "emph" }
        return ""
    }

    /// The nearest supported effect to a PowerPoint preset, in the same class. Emphasis other than a full turn,
    /// motion paths and object verbs have none.
    static func effect(presetClass: String, id: Int?, subtype: Int, behaviors: [XNode]) -> AnimationEffect? {
        // Without a preset, an effect that only shows or hides its element is Appear or Disappear.
        let onlyShowsOrHides = id == nil && !behaviors.isEmpty && behaviors.allSatisfy { $0.name == "set" }
        switch presetClass {
        case "entr":
            switch movement(id, subtype: subtype, entering: true) {
            case .left?: return .flyInFromLeft
            case .right?: return .flyInFromRight
            case .top?: return .flyInFromTop
            case .bottom?: return .flyInFromBottom
            case nil: break
            }
            if id == 1 || onlyShowsOrHides { return .appear }
            if let id, zoomPresets.contains(id) { return .zoomIn }
            return .fadeIn
        case "exit":
            switch movement(id, subtype: subtype, entering: false) {
            case .left?: return .flyOutToLeft
            case .right?: return .flyOutToRight
            case .top?: return .flyOutToTop
            case .bottom?: return .flyOutToBottom
            case nil: break
            }
            if id == 1 || onlyShowsOrHides { return .disappear }
            if let id, zoomPresets.contains(id) { return .zoomOut }
            return .fadeOut
        case "emph":
            if id == 8 { return .spin }
            // A turn with no preset, if it's a whole one.
            if id == nil, let turn = behaviors.first(where: { $0.name == "animRot" }), let by = PPTXValue.double(turn["by"]),
               abs(by) >= 21_600_000 {
                return .spin
            }
            return nil
        default:
            return nil
        }
    }

    /// Presets that grow or shrink the element: Zoom, Faded Zoom, Expand, Grow & Turn, Compress, Stretch, Zip,
    /// Spinner, Pinwheel, Spiral and Center Revolve.
    static let zoomPresets: Set<Int> = [15, 17, 23, 31, 35, 43, 49, 50, 51, 53, 55]

    private enum Edge { case left, right, top, bottom }

    /// The side a moving preset comes from (or leaves by): Fly, Crawl and Peek by their direction; the presets
    /// that rise, sink or slide by their nature.
    private static func movement(_ id: Int?, subtype: Int, entering: Bool) -> Edge? {
        switch id {
        case 2?, 7?, 12?:
            switch subtype {
            case 1: return .top
            case 2, 3, 6: return .right
            case 8, 9, 12: return .left
            default: return .bottom
            }
        case 26?: return entering ? .top : .bottom // Bounce
        case 28?: return entering ? .bottom : .top // Credits
        case 30?: return entering ? .bottom : .top // Float
        case 34?: return .right // Light Speed
        case 37?: return .bottom // Rise Up, Sink Down
        case 42?: return .bottom // Ascend in, Descend out
        case 47?: return .top // Descend in, Ascend out
        case 52?: return .bottom // Arc Up in, Curve Down out
        default: return nil
        }
    }

    // MARK: Paragraph builds

    /// Consecutive effects building one shape's paragraphs (same shape, build group and preset) become one
    /// by-paragraph animation. A build that leaves out some of the shape's paragraphs can't be kept exactly.
    private mutating func merged(_ effects: [Effect]) -> [SlideAnimation] {
        var animations: [SlideAnimation] = []
        var index = 0
        while index < effects.count {
            let first = effects[index]
            var covered = Set<Int>()
            var next = index + 1
            if let range = first.paragraphs {
                covered.formUnion(range)
                while next < effects.count, let range = effects[next].paragraphs, effects[next].spid == first.spid,
                      effects[next].groupID == first.groupID, effects[next].preset == first.preset {
                    covered.formUnion(range)
                    next += 1
                }
            }
            guard let element = elements[first.spid] else {
                index = next
                continue
            }
            if first.paragraphs != nil {
                let text = element.shape?.text
                let wanted = Set(text.map { body in body.paragraphs.indices.filter { !body.paragraphs[$0].isEmpty } } ?? [])
                if wanted.isEmpty || !wanted.isSubset(of: covered) || !covered.isSubset(of: Set(text?.paragraphs.indices ?? 0..<0)) {
                    result.hasUnsupported = true
                }
            }
            // Instant effects have no duration in the file; they keep the default.
            let duration = first.effect.isInstant ? SlideAnimation(elementID: element.id).duration : first.duration ?? 0.5
            animations.append(SlideAnimation(elementID: element.id, effect: first.effect, start: first.start, duration: duration,
                                             delay: first.delay, byParagraph: first.paragraphs != nil))
            index = next
        }
        return animations
    }
}
