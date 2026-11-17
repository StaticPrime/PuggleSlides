import Foundation

/// Slide transitions and object animations as LibreOffice Impress writes them: SMIL transition types on the
/// drawing-page style (and a transition filter in the page's timing root, which carries the exact duration), and
/// a main sequence of click groups holding LibreOffice's effect presets.
enum ODPMotion {
    // MARK: Transitions

    /// The SMIL type and subtype each transition is written as, using LibreOffice's transitions: Fade Smoothly,
    /// Dissolve, Push, Turn Around (a flip), Outside Turning Cube, and Cover for the gallery.
    static func smil(_ kind: TransitionKind) -> (type: String, subtype: String?)? {
        switch kind {
        case .none: nil
        case .dissolve: ("dissolve", nil)
        case .fade: ("fade", "crossfade")
        case .slideFromRight: ("pushWipe", "fromRight")
        case .slideFromLeft: ("pushWipe", "fromLeft")
        case .flip: ("miscShapeWipe", "topToBottom")
        case .cube: ("miscShapeWipe", "cornersOut")
        case .gallery: ("slideWipe", "fromRight")
        }
    }

    /// LibreOffice's coarse speeds, for apps that read only those.
    static func speed(_ duration: Double) -> String {
        duration <= 0.5 ? "fast" : duration <= 0.75 ? "medium" : "slow"
    }

    static func duration(speed: String?) -> Double {
        switch speed {
        case "fast": 0.5
        case "slow": 1
        case "medium": 0.75
        default: SlideTransition.defaultDuration
        }
    }

    /// The transition a SMIL type stands for; transitions PuggleSlides doesn't have become the nearest it does.
    static func kind(type: String, subtype: String?, reverse: Bool) -> TransitionKind {
        let subtype = subtype ?? ""
        switch type {
        case "dissolve":
            return .dissolve
        case "fade":
            return .fade
        case "pushWipe", "slideWipe":
            if type == "slideWipe", subtype == "fromRight", !reverse { return .gallery }
            let fromRight = subtype == "fromRight" || subtype == "fromBottom" || subtype == "fromBottomRight" || subtype == "fromTopRight"
            return fromRight != reverse ? .slideFromRight : .slideFromLeft
        case "miscShapeWipe":
            switch subtype {
            case "topToBottom", "bottomToTop", "leftToRight", "rightToLeft": return .flip
            case "cornersOut", "cornersIn", "acrossEmbed": return .cube
            default: return .fade
            }
        case "":
            return .none
        default:
            return .fade
        }
    }

    /// The transitions of `presentation:transition-style`, which older files use instead of SMIL types.
    static func kind(legacyStyle: String) -> TransitionKind {
        switch legacyStyle {
        case "none": .none
        case "dissolve": .dissolve
        case let style where style.hasPrefix("move-from-right") || style.hasPrefix("uncover-to-left") || style.hasSuffix("from-right"):
            .slideFromRight
        case let style where style.hasPrefix("move-from-left") || style.hasPrefix("uncover-to-right") || style.hasSuffix("from-left"):
            .slideFromLeft
        default: .fade
        }
    }

    // MARK: Writing animations

    /// One effect node: an animation, one paragraph of an animation that plays by paragraph, or a clip's play command.
    private struct Unit {
        /// Nil: Impress's Start media effect, which plays the clip `target` names.
        var animation: SlideAnimation?
        var target: String
        var start: AnimationStart
        var groupID: Int?
    }

    /// The timing root of a slide: its transition filter, main sequence and clips' own sequences. `targets` gives each
    /// element's id and its non-empty paragraphs' ids, `clips` each clip's id. Clips that start as the slide appears are
    /// started with its first effects, clips that start on a click by a click after its animations, and clips played
    /// manually by a sequence their own click triggers, which toggles them. Nil when the slide has none of these.
    static func timing(for slide: Slide, pageID: String, targets: [UUID: (shape: String, paragraphs: [String])],
                       clips: [(target: String, clip: MediaClip)] = []) -> String? {
        var units: [Unit] = []
        var group = 0
        for animation in slide.animations {
            guard let target = targets[animation.elementID] else { continue }
            if animation.byParagraph, target.paragraphs.count > 0 {
                group += 1
                for (index, paragraph) in target.paragraphs.enumerated() {
                    let start: AnimationStart = index == 0 ? animation.start : (animation.start == .onClick ? .onClick : .afterPrevious)
                    units.append(Unit(animation: animation, target: paragraph, start: start, groupID: group))
                }
            } else {
                units.append(Unit(animation: animation, target: target.shape, start: animation.start, groupID: nil))
            }
        }
        units = clips.filter { $0.clip.playback == .automatically }.map { Unit(target: $0.target, start: .withPrevious) } + units
            + clips.filter { $0.clip.playback == .onClick }.map { Unit(target: $0.target, start: .onClick) }
        let manual = clips.filter { $0.clip.playback == .manually }.map(\.target)
        let transition = slide.transition.flatMap { transition in smil(transition.kind).map { (transition, $0) } }
        guard transition != nil || !units.isEmpty || !manual.isEmpty else { return nil }

        var xml = XMLWriter(fragmentCapacity: 1024 + units.count * 600)
        xml.raw("<anim:par presentation:node-type=\"timing-root\">")
        if let (transition, smil) = transition {
            xml.raw("<anim:par")
            xml.attribute("smil:begin", pageID + ".begin")
            xml.raw("><anim:transitionFilter smil:dur=\"\(ODFFormat.seconds(transition.duration))\"")
            xml.attribute("smil:type", smil.type)
            if let subtype = smil.subtype { xml.attribute("smil:subtype", subtype) }
            xml.raw("/></anim:par>")
        }
        if !units.isEmpty {
            // Click groups hold timeline groups; with-previous effects share one, after-previous starts the next.
            var clickGroups: [(automatic: Bool, timelines: [[Unit]])] = []
            for unit in units {
                switch unit.start {
                case .onClick:
                    clickGroups.append((false, [[unit]]))
                case .withPrevious:
                    if clickGroups.isEmpty { clickGroups.append((true, [[]])) }
                    clickGroups[clickGroups.count - 1].timelines[clickGroups[clickGroups.count - 1].timelines.count - 1].append(unit)
                case .afterPrevious:
                    if clickGroups.isEmpty {
                        clickGroups.append((true, [[unit]]))
                    } else {
                        clickGroups[clickGroups.count - 1].timelines.append([unit])
                    }
                }
            }
            xml.raw("<anim:seq presentation:node-type=\"main-sequence\">")
            for clickGroup in clickGroups {
                xml.raw(clickGroup.automatic ? "<anim:par smil:begin=\"0s\">" : "<anim:par smil:begin=\"next\">")
                var offset = 0.0
                for timeline in clickGroup.timelines {
                    xml.raw("<anim:par smil:begin=\"\(ODFFormat.seconds(offset))\">")
                    var length = 0.0
                    for unit in timeline {
                        effect(unit, into: &xml)
                        if let animation = unit.animation {
                            length = max(length, animation.delay + (animation.effect.isInstant ? 0 : animation.duration))
                        }
                    }
                    xml.raw("</anim:par>")
                    offset += length
                }
                xml.raw("</anim:par>")
            }
            xml.raw("</anim:seq>")
        }
        for target in manual {
            // A trigger, as Impress writes one: its click group begins when the clip is clicked.
            xml.raw("<anim:seq presentation:node-type=\"interactive-sequence\" smil:restart=\"whenNotActive\"><anim:par")
            xml.attribute("smil:begin", target + ".click")
            xml.raw("><anim:par smil:begin=\"0s\">")
            mediaCommand(target: target, nodeType: "on-click", preset: "ooo-media-toggle-pause", command: "toggle-pause", into: &xml)
            xml.raw("</anim:par></anim:par></anim:seq>")
        }
        xml.raw("</anim:par>")
        return String(decoding: xml.bytes, as: UTF8.self)
    }

    /// Impress's media effects: Start plays the clip, Toggle Pause plays or pauses it.
    private static func mediaCommand(target: String, nodeType: String, preset: String, command: String, into xml: inout XMLWriter) {
        xml.raw("<anim:par smil:begin=\"0s\" smil:fill=\"hold\" presentation:node-type=\"\(nodeType)\" presentation:preset-class=\"media-call\"")
        xml.raw(" presentation:preset-id=\"\(preset)\"><anim:command smil:begin=\"0s\"")
        xml.attribute("smil:targetElement", target)
        xml.raw(" anim:command=\"\(command)\"/></anim:par>")
    }

    private static func presetSubtype(_ effect: AnimationEffect) -> String? {
        switch effect {
        case .flyInFromLeft, .flyOutToLeft: "from-left"
        case .flyInFromRight, .flyOutToRight: "from-right"
        case .flyInFromTop, .flyOutToTop: "from-top"
        case .flyInFromBottom, .flyOutToBottom: "from-bottom"
        case .zoomIn: "in"
        case .zoomOut: "out"
        default: nil
        }
    }

    private static func presetID(_ effect: AnimationEffect) -> String {
        switch effect {
        case .appear: "ooo-entrance-appear"
        case .fadeIn: "ooo-entrance-fade-in"
        case .flyInFromLeft, .flyInFromRight, .flyInFromTop, .flyInFromBottom: "ooo-entrance-fly-in"
        case .zoomIn: "ooo-entrance-zoom"
        case .spin: "ooo-emphasis-spin"
        case .disappear: "ooo-exit-disappear"
        case .fadeOut: "ooo-exit-fade-out"
        case .flyOutToLeft, .flyOutToRight, .flyOutToTop, .flyOutToBottom: "ooo-exit-fly-out"
        case .zoomOut: "ooo-exit-zoom"
        }
    }

    private static func effect(_ unit: Unit, into xml: inout XMLWriter) {
        let nodeType = switch unit.start {
        case .onClick: "on-click"
        case .withPrevious: "with-previous"
        case .afterPrevious: "after-previous"
        }
        guard let animation = unit.animation else {
            mediaCommand(target: unit.target, nodeType: nodeType, preset: "ooo-media-start", command: "play", into: &xml)
            return
        }
        let effect = animation.effect
        let presetClass = effect.isEntrance ? "entrance" : effect.isExit ? "exit" : "emphasis"
        xml.raw("<anim:par smil:begin=\"\(ODFFormat.seconds(animation.delay))\" smil:fill=\"hold\" presentation:node-type=\"\(nodeType)\"")
        xml.raw(" presentation:preset-class=\"\(presetClass)\" presentation:preset-id=\"\(presetID(effect))\"")
        if let subtype = presetSubtype(effect) { xml.raw(" presentation:preset-sub-type=\"\(subtype)\"") }
        if let group = unit.groupID { xml.raw(" presentation:group-id=\"\(group)\"") }
        xml.raw(">")
        let duration = ODFFormat.seconds(animation.duration)
        var target = XMLWriter(fragmentCapacity: 64)
        target.attribute("smil:targetElement", unit.target)
        let targetAttribute = String(decoding: target.bytes, as: UTF8.self)
        func set(_ value: String, begin: Double = 0) {
            xml.raw("<anim:set smil:begin=\"\(ODFFormat.seconds(begin))\" smil:dur=\"0.001s\" smil:fill=\"hold\"\(targetAttribute)")
            xml.raw(" smil:attributeName=\"visibility\" smil:to=\"\(value)\"/>")
        }
        func animate(_ attribute: String, _ values: String) {
            xml.raw("<anim:animate smil:dur=\"\(duration)\" smil:fill=\"hold\"\(targetAttribute) smil:attributeName=\"\(attribute)\"")
            xml.raw(" smil:values=\"\(values)\" smil:keyTimes=\"0;1\"/>")
        }
        let exitBegin = max(0, animation.duration - 0.001)
        switch effect {
        case .appear:
            set("visible")
        case .fadeIn:
            set("visible")
            xml.raw("<anim:transitionFilter smil:dur=\"\(duration)\"\(targetAttribute) smil:type=\"fade\" smil:subtype=\"crossfade\"/>")
        case .flyInFromLeft, .flyInFromRight, .flyInFromTop, .flyInFromBottom:
            set("visible")
            animate("x", effect == .flyInFromLeft ? "0-width/2;x" : effect == .flyInFromRight ? "1+width/2;x" : "x;x")
            animate("y", effect == .flyInFromTop ? "0-height/2;y" : effect == .flyInFromBottom ? "1+height/2;y" : "y;y")
        case .zoomIn:
            set("visible")
            animate("width", "0;width")
            animate("height", "0;height")
        case .spin:
            xml.raw("<anim:animateTransform smil:dur=\"\(duration)\" smil:fill=\"hold\"\(targetAttribute) smil:attributeName=\"transform\" smil:by=\"360\" svg:type=\"rotate\"/>")
        case .disappear:
            set("hidden")
        case .fadeOut:
            xml.raw("<anim:transitionFilter smil:dur=\"\(duration)\"\(targetAttribute) smil:type=\"fade\" smil:subtype=\"crossfade\" smil:mode=\"out\"/>")
            set("hidden", begin: exitBegin)
        case .flyOutToLeft, .flyOutToRight, .flyOutToTop, .flyOutToBottom:
            animate("x", effect == .flyOutToLeft ? "x;0-width/2" : effect == .flyOutToRight ? "x;1+width/2" : "x;x")
            animate("y", effect == .flyOutToTop ? "y;0-height/2" : effect == .flyOutToBottom ? "y;1+height/2" : "y;y")
            set("hidden", begin: exitBegin)
        case .zoomOut:
            animate("width", "width;0")
            animate("height", "height;0")
            set("hidden", begin: exitBegin)
        }
        xml.raw("</anim:par>")
    }

    // MARK: Reading

    /// A slide's transition from its drawing-page style and timing root.
    static func transition(page: ODFPageProperties, timing: ODFNode?) -> SlideTransition? {
        var filter: ODFNode?
        for child in timing?.elements ?? [] where child.name == "anim:par" {
            if let found = child.children.first(where: { $0.name == "anim:transitionFilter" }), child["presentation:node-type"] == nil {
                filter = found
                break
            }
        }
        var kind: TransitionKind?
        if let type = page.transitionType, !type.isEmpty {
            kind = Self.kind(type: type, subtype: page.transitionSubtype, reverse: page.transitionReverse ?? false)
        } else if let type = filter?["smil:type"] {
            kind = Self.kind(type: type, subtype: filter?["smil:subtype"], reverse: filter?["smil:direction"] == "reverse")
        } else if let legacy = page.legacyTransition {
            kind = Self.kind(legacyStyle: legacy)
        }
        guard let kind, kind != .none else { return nil }
        let duration = ODFValue.seconds(filter?["smil:dur"]) ?? duration(speed: page.transitionSpeed)
        return SlideTransition(kind: kind, duration: min(max(duration, 0), 60))
    }

    /// What an animation target id names: an element, or one of its paragraphs.
    struct Target {
        var element: UUID
        var paragraph: Int?
    }

    private struct ReadEffect {
        var target: Target
        var effect: AnimationEffect
        var start: AnimationStart
        var duration: Double
        var delay: Double
        var group: String?
        /// A media effect: it plays `clip`, or something that isn't kept.
        var isMedia = false
        var clip: UUID?
    }

    /// The slide's main sequence as animations. Effects PuggleSlides doesn't have map to the nearest one; motion paths,
    /// most emphasis effects and interactive sequences are dropped with a warning.
    ///
    /// Media effects tell how the clips `clips` names by id start: a Start or Toggle Pause media effect in the main sequence
    /// plays a clip as the slide appears when no click comes before it, else on a click; a sequence the clip's own click
    /// triggers, playing or pausing it, plays it manually. Clips without either aren't in `playback`.
    static func animations(timing: ODFNode?, targets: [String: Target], clips: [String: UUID], playback: inout [UUID: MediaPlayback],
                           warnings: inout Set<ImportWarning>) -> [SlideAnimation] {
        guard let timing else { return [] }
        var effects: [ReadEffect] = []
        var triggered: [UUID] = []
        for child in timing.elements {
            switch child["presentation:node-type"] {
            case "main-sequence":
                read(sequence: child, targets: targets, clips: clips, into: &effects, warnings: &warnings)
            case "interactive-sequence":
                if let clip = mediaTrigger(child, clips: clips) { triggered.append(clip) } else { warnings.insert(.animations) }
            default:
                // The transition's own node, and audio.
                if child.firstDescendant("anim:audio") != nil { warnings.insert(.audio) }
            }
        }
        // Media effects play clips; the effect after one that took a click takes the click.
        var kept: [ReadEffect] = []
        var clicked = false
        var pendingClick = false
        for var effect in effects {
            if effect.start == .onClick { clicked = true }
            guard !effect.isMedia else {
                if let clip = effect.clip, playback[clip] == nil { playback[clip] = clicked ? .onClick : .automatically }
                if effect.start == .onClick { pendingClick = true }
                continue
            }
            if pendingClick { effect.start = .onClick }
            pendingClick = false
            kept.append(effect)
        }
        for clip in triggered where playback[clip] == nil { playback[clip] = .manually }
        effects = kept
        // Consecutive effects on paragraphs of one element, with one effect, are one animation by paragraph.
        var result: [SlideAnimation] = []
        var index = 0
        while index < effects.count {
            let first = effects[index]
            var end = index + 1
            if first.target.paragraph != nil {
                while end < effects.count, effects[end].target.element == first.target.element, effects[end].target.paragraph != nil,
                      effects[end].effect == first.effect, effects[end].group == first.group, effects[end].start != .withPrevious {
                    end += 1
                }
            }
            result.append(SlideAnimation(elementID: first.target.element, effect: first.effect, start: first.start,
                                         duration: first.duration, delay: first.delay, byParagraph: first.target.paragraph != nil))
            index = end
        }
        return result
    }

    /// The clip whose own click triggers a sequence that only plays or pauses it.
    private static func mediaTrigger(_ sequence: ODFNode, clips: [String: UUID]) -> UUID? {
        var trigger: String?
        for begin in ([sequence["smil:begin"]] + sequence.elements.map { $0["smil:begin"] }).compactMap({ $0 }) {
            guard let range = begin.range(of: ".click") else { continue }
            let id = String(begin[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if trigger == nil { trigger = id } else if trigger != id { return nil }
        }
        guard let trigger, let clip = clips[trigger] else { return nil }
        let commands = leaves(of: sequence)
        let plays = commands.contains { ["play", "toggle-pause"].contains($0["anim:command"] ?? "") }
        return plays && commands.allSatisfy({ $0.name == "anim:command" && $0["smil:targetElement"] == trigger }) ? clip : nil
    }

    /// Every leaf below a node: what's in its par, seq and iterate nodes.
    private static func leaves(of node: ODFNode) -> [ODFNode] {
        var leaves: [ODFNode] = []
        func collect(_ node: ODFNode, depth: Int) {
            guard depth < 16 else { return }
            for child in node.elements {
                if ["anim:par", "anim:seq", "anim:iterate"].contains(child.name) { collect(child, depth: depth + 1) } else { leaves.append(child) }
            }
        }
        collect(node, depth: 0)
        return leaves
    }

    private static func read(sequence: ODFNode, targets: [String: Target], clips: [String: UUID], into effects: inout [ReadEffect],
                             warnings: inout Set<ImportWarning>) {
        for clickGroup in sequence.elements where clickGroup.name == "anim:par" || clickGroup.name == "anim:seq" {
            let clickStarts = !(clickGroup["smil:begin"].map { ODFValue.seconds($0) != nil } ?? false)
            for (timelineIndex, timeline) in clickGroup.elements.enumerated() where timeline.name == "anim:par" || timeline.name == "anim:seq" {
                for (effectIndex, node) in timeline.elements.enumerated() {
                    let inferred: AnimationStart = effectIndex > 0 ? .withPrevious
                        : timelineIndex == 0 ? (clickStarts ? .onClick : .afterPrevious) : .afterPrevious
                    if let effect = effect(node, inferredStart: inferred, targets: targets, clips: clips, warnings: &warnings) { effects.append(effect) }
                }
            }
        }
    }

    private static func effect(_ node: ODFNode, inferredStart: AnimationStart, targets: [String: Target], clips: [String: UUID],
                               warnings: inout Set<ImportWarning>) -> ReadEffect? {
        let start: AnimationStart = switch node["presentation:node-type"] {
        case "on-click": .onClick
        case "with-previous": .withPrevious
        case "after-previous": .afterPrevious
        default: inferredStart
        }
        let presetClass = node["presentation:preset-class"] ?? ""
        // Every leaf below the effect node, nested iterate and par nodes included.
        let leaves = leaves(of: node)
        if presetClass == "media-call" || (presetClass.isEmpty && !leaves.isEmpty && leaves.allSatisfy { $0.name == "anim:command" }) {
            // A media effect: playing a clip starts it; stopping it can't be kept; one on media that wasn't kept goes with it.
            var effect = ReadEffect(target: Target(element: UUID(), paragraph: nil), effect: .appear, start: start, duration: 0, delay: 0,
                                    isMedia: true)
            let commands = leaves.filter { $0.name == "anim:command" }
            guard let target = commands.lazy.compactMap({ $0["smil:targetElement"] }).first, let clip = clips[target] else { return effect }
            if commands.contains(where: { ["play", "toggle-pause"].contains($0["anim:command"] ?? "") }) {
                effect.clip = clip
            } else {
                warnings.insert(.animations)
            }
            return effect
        }
        if presetClass == "motion-path" || presetClass == "ole-action" {
            warnings.insert(.animations)
            return nil
        }
        if leaves.contains(where: { $0.name == "anim:audio" }) { warnings.insert(.audio) }
        var targetID = leaves.lazy.compactMap { $0["smil:targetElement"] }.first
        if targetID == nil { targetID = node.firstDescendant("anim:iterate")?["smil:targetElement"] }
        guard let targetID, let target = targets[targetID] else {
            if !leaves.isEmpty { warnings.insert(.animations) }
            return nil
        }
        guard let effect = effectKind(presetID: node["presentation:preset-id"] ?? "", presetClass: presetClass,
                                      subtype: node["presentation:preset-sub-type"] ?? "", leaves: leaves) else {
            warnings.insert(.animations)
            return nil
        }
        let durations = leaves.compactMap { leaf -> Double? in
            guard let value = ODFValue.seconds(leaf["smil:dur"]), value > 0.01 else { return nil }
            return value
        }
        let duration = durations.max() ?? ODFValue.seconds(node["smil:dur"]) ?? 0.5
        let delay = ODFValue.seconds(node["smil:begin"]) ?? 0
        return ReadEffect(target: target, effect: effect, start: start, duration: min(max(duration, 0), 600), delay: min(max(delay, 0), 600),
                          group: node["presentation:group-id"])
    }

    /// The effect a LibreOffice preset (or, without one, the effect's nodes) stands for.
    static func effectKind(presetID: String, presetClass: String, subtype: String, leaves: [ODFNode]) -> AnimationEffect? {
        let direction = subtype.replacingOccurrences(of: "from-", with: "").split(separator: "-").first.map(String.init) ?? ""
        let hasFilter = leaves.contains { $0.name == "anim:transitionFilter" }
        func entering(_ edge: String) -> AnimationEffect {
            switch edge {
            case "left": .flyInFromLeft
            case "right": .flyInFromRight
            case "top": .flyInFromTop
            default: .flyInFromBottom
            }
        }
        func exiting(_ edge: String) -> AnimationEffect {
            switch edge {
            case "left": .flyOutToLeft
            case "right": .flyOutToRight
            case "top": .flyOutToTop
            default: .flyOutToBottom
            }
        }
        let name = presetID.lowercased()
        if name.hasPrefix("ooo-entrance-") {
            let effect = name.dropFirst("ooo-entrance-".count)
            switch effect {
            case "appear": return .appear
            case "fade-in", "dissolve-in", "fade-in-and-swivel": return .fadeIn
            case "fly-in", "fly-in-slow", "peek-in", "crawl-in", "glide", "flip": return entering(direction.isEmpty ? "bottom" : direction)
            case "ascend", "rise-up", "float": return .flyInFromBottom
            case "descend", "sink-down": return .flyInFromTop
            case "zoom", "expand", "grow-and-turn", "stretchy", "compress", "spin-in", "spiral-in", "fade-in-and-zoom", "basic-zoom",
                 "magnify", "pinwheel", "swish", "boomerang", "curve-up", "light-speed", "thread", "unfold", "whip", "contract":
                return .zoomIn
            default: return hasFilter ? .fadeIn : .appear
            }
        }
        if name.hasPrefix("ooo-exit-") {
            let effect = name.dropFirst("ooo-exit-".count)
            switch effect {
            case "disappear": return .disappear
            case "fade-out", "dissolve", "fade-out-and-swivel": return .fadeOut
            case "fly-out", "fly-out-slow", "peek-out", "crawl-out", "glide", "flip": return exiting(direction.isEmpty ? "bottom" : direction)
            case "ascend", "float", "rise-up": return .flyOutToTop
            case "descend", "sink-down": return .flyOutToBottom
            case "zoom", "contract", "collapse", "shrink-and-turn", "stretchy", "spin-out", "spiral-out", "fade-out-and-zoom", "basic-zoom",
                 "magnify", "pinwheel", "swish", "boomerang", "curve-down", "light-speed", "thread", "fold", "whip", "expand":
                return .zoomOut
            default: return hasFilter ? .fadeOut : .disappear
            }
        }
        if name == "ooo-emphasis-spin" { return .spin }
        if name.hasPrefix("ooo-emphasis-") { return nil }
        // No preset: judge by the nodes.
        let visibility = leaves.first { $0.name == "anim:set" && $0["smil:attributeName"] == "visibility" }?["smil:to"]
        let isExit = presetClass == "exit" || visibility == "hidden" || leaves.contains { $0["smil:mode"] == "out" }
        if leaves.contains(where: { $0.name == "anim:animateTransform" && $0["svg:type"] == "rotate" }) { return .spin }
        if hasFilter { return isExit ? .fadeOut : .fadeIn }
        let animated = leaves.filter { $0.name == "anim:animate" }
        if let motion = animated.first(where: { ($0["smil:attributeName"] == "x" || $0["smil:attributeName"] == "y") && !($0["smil:values"] ?? "").isEmpty }) {
            let values = motion["smil:values"] ?? ""
            let horizontal = motion["smil:attributeName"] == "x"
            let offscreen = values.split(separator: ";").first { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(horizontal ? "x" : "y") } ?? ""
            let low = offscreen.hasPrefix("0") || offscreen.hasPrefix("-")
            let edge = horizontal ? (low ? "left" : "right") : (low ? "top" : "bottom")
            return isExit ? exiting(edge) : entering(edge)
        }
        if animated.contains(where: { $0["smil:attributeName"] == "width" || $0["smil:attributeName"] == "height" }) {
            return isExit ? .zoomOut : .zoomIn
        }
        if visibility != nil { return isExit ? .disappear : .appear }
        if presetClass == "emphasis" { return nil }
        return isExit ? .disappear : (presetClass == "entrance" ? .appear : nil)
    }
}
