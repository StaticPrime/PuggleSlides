import Foundation

/// PowerPoint's animation presets for PuggleSlides' effects: preset class, id and subtype (fly directions are
/// 1 top, 2 right, 4 bottom, 8 left; zoom is 16 in, 32 out).
enum PPTXAnimationPresets {
    static func preset(_ effect: AnimationEffect) -> (presetClass: String, id: Int, subtype: Int) {
        switch effect {
        case .appear: ("entr", 1, 0)
        case .fadeIn: ("entr", 10, 0)
        case .flyInFromLeft: ("entr", 2, 8)
        case .flyInFromRight: ("entr", 2, 2)
        case .flyInFromBottom: ("entr", 2, 4)
        case .flyInFromTop: ("entr", 2, 1)
        case .zoomIn: ("entr", 53, 16)
        case .spin: ("emph", 8, 0)
        case .disappear: ("exit", 1, 0)
        case .fadeOut: ("exit", 10, 0)
        case .flyOutToLeft: ("exit", 2, 8)
        case .flyOutToRight: ("exit", 2, 2)
        case .flyOutToBottom: ("exit", 2, 4)
        case .flyOutToTop: ("exit", 2, 1)
        case .zoomOut: ("exit", 53, 32)
        }
    }

    /// Where a fly effect starts (entrances) or ends (exits), in PowerPoint's slide-relative formulas.
    static func offSlide(_ effect: AnimationEffect) -> (attribute: String, value: String)? {
        switch effect {
        case .flyInFromLeft, .flyOutToLeft: ("ppt_x", "0-#ppt_w/2")
        case .flyInFromRight, .flyOutToRight: ("ppt_x", "1+#ppt_w/2")
        case .flyInFromBottom, .flyOutToBottom: ("ppt_y", "1+#ppt_h/2")
        case .flyInFromTop, .flyOutToTop: ("ppt_y", "0-#ppt_h/2")
        default: nil
        }
    }
}

/// What the part writer recorded about an element it wrote.
struct PPTXWrittenShape {
    /// How the slide's build list names an element's animations, as PowerPoint writes it.
    enum Build {
        /// A `p:sp`: a paragraph build (`bldP`), which by-paragraph animations need.
        case paragraphs
        /// A chart's graphic frame: `bldGraphic`, built as one.
        case graphic
        /// Pictures, connectors, groups and tables: no entry.
        case none
    }

    /// What PowerPoint calls the element: a shape, connector, picture, group or graphic frame.
    enum Kind {
        case shape, connector, picture, group, graphicFrame

        /// Its drawing element moniker, which modern comments name it by ([MS-ODRAWXML] 2.29.3.20).
        var moniker: String {
            switch self {
            case .shape: "spMk"
            case .connector: "cxnSpMk"
            case .picture: "picMk"
            case .group: "grpSpMk"
            case .graphicFrame: "graphicFrameMk"
            }
        }
    }

    /// The `cNvPr` id.
    var id: Int
    var build: Build
    var kind = Kind.shape
}

/// Writes a slide's animations as PowerPoint's timing tree: the main sequence holds one group per click (the
/// first starts with the slide when it isn't on click), each group holds one group per "after previous" step
/// starting where the step before ends, and each step holds the effects that run together.
///
/// Clips join it as PowerPoint plays them: one that starts automatically is played (`playFrom(0.0)`, the Play media
/// effect) with the first effects, as the slide appears; one that starts on click is played by a click after the
/// slide's animations; one played manually has a sequence its own click triggers, which toggles it (the Pause media
/// effect, `togglePause`). Every clip has a media node with its volume, mute, loop, whether it shows while stopped and
/// whether a sound plays across slides (999 of them, ended only by a stop-audio event).
struct PPTXAnimationWriter {
    private struct Instance {
        /// Nil: a clip's play command.
        var animation: SlideAnimation?
        var spid: Int
        var paragraph: Int?
        var start: AnimationStart
        var groupID: Int?

        var delay: Int { animation.map { PPTXValue.clamped($0.delay * 1000, 0...86_400_000) } ?? 0 }
        var duration: Int { animation.map { PPTXValue.clamped($0.duration * 1000, 0...86_400_000) } ?? 1 }
        /// How long the effect takes; instant effects and play commands take none.
        var length: Int { animation.map { $0.effect.isInstant ? 0 : duration } ?? 0 }
    }

    private var xml: XMLWriter
    private var nextID = 1

    private init(xml: XMLWriter) {
        self.xml = xml
    }

    static func write(_ slide: Slide, shapes: [UUID: PPTXWrittenShape], clips: [PPTXWrittenClip] = [], into xml: inout XMLWriter) {
        var writer = PPTXAnimationWriter(xml: XMLWriter(fragmentCapacity: 4096))
        guard writer.timing(slide, shapes: shapes, clips: clips) else { return }
        xml.append(writer.xml)
    }

    /// Text paragraphs a by-paragraph build animates: those with text.
    private static func paragraphs(of element: SlideElement) -> [Int] {
        guard let text = element.shape?.text else { return [] }
        return text.paragraphs.indices.filter { !text.paragraphs[$0].isEmpty }
    }

    private mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private mutating func timing(_ slide: Slide, shapes: [UUID: PPTXWrittenShape], clips: [PPTXWrittenClip]) -> Bool {
        var elements: [UUID: SlideElement] = [:]
        for element in slide.elements where elements[element.id] == nil { elements[element.id] = element }
        var instances: [Instance] = []
        var nextGroup: [Int: Int] = [:]
        var builds: [(spid: Int, groupID: Int, levels: Int?, background: Bool, graphic: Bool)] = []
        for animation in slide.animations {
            guard let element = elements[animation.elementID], let shape = shapes[animation.elementID] else { continue }
            var groupID: Int?
            if shape.build != .none {
                let next = nextGroup[shape.id, default: 0]
                nextGroup[shape.id] = next + 1
                groupID = next
            }
            let paragraphs = animation.byParagraph ? Self.paragraphs(of: element) : []
            if paragraphs.isEmpty {
                instances.append(Instance(animation: animation, spid: shape.id, start: animation.start, groupID: groupID))
            } else {
                for (number, index) in paragraphs.enumerated() {
                    // Each paragraph takes its own click; otherwise each follows the one before.
                    let start = number == 0 ? animation.start : animation.start == .onClick ? .onClick : .afterPrevious
                    instances.append(Instance(animation: animation, spid: shape.id, paragraph: index, start: start, groupID: groupID))
                }
            }
            if let groupID {
                let style = element.shape
                let background = (style?.fill.map { !$0.isNone } ?? false) || (style?.outline?.isVisible ?? false)
                let deepest = paragraphs.compactMap { element.shape?.text?.paragraphs[$0].level }.max()
                builds.append((shape.id, groupID, paragraphs.isEmpty ? nil : (deepest ?? 0) + 1, background, shape.build == .graphic))
            }
        }
        // Clips that start by themselves play first, as the slide appears; clips that start on a click, after the animations.
        instances = clips.filter { $0.clip.playback == .automatically }.map { Instance(spid: $0.spid, start: .withPrevious) } + instances
            + clips.filter { $0.clip.playback == .onClick }.map { Instance(spid: $0.spid, start: .onClick) }
        guard !instances.isEmpty || !clips.isEmpty else { return false }

        xml.raw("<p:timing><p:tnLst><p:par><p:cTn id=\"\(takeID())\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>")
        if !instances.isEmpty { mainSequence(instances) }
        for clip in clips {
            if clip.clip.playback == .manually { trigger(clip) }
            mediaNode(clip)
        }
        xml.raw("</p:childTnLst></p:cTn></p:par></p:tnLst>")
        if !builds.isEmpty {
            xml.raw("<p:bldLst>")
            for build in builds {
                if build.graphic {
                    xml.raw("<p:bldGraphic spid=\"\(build.spid)\" grpId=\"\(build.groupID)\"><p:bldAsOne/></p:bldGraphic>")
                    continue
                }
                xml.raw("<p:bldP spid=\"\(build.spid)\" grpId=\"\(build.groupID)\"")
                if let levels = build.levels {
                    xml.raw(" build=\"p\"")
                    if levels > 1 { xml.raw(" bldLvl=\"\(min(levels, 9))\"") }
                }
                if build.background { xml.raw(" animBg=\"1\"") }
                xml.raw("/>")
            }
            xml.raw("</p:bldLst>")
        }
        xml.raw("</p:timing>")
        return true
    }

    /// The main sequence: click groups of "after previous" steps of effects that run together.
    private mutating func mainSequence(_ instances: [Instance]) {
        var groups: [[[Instance]]] = []
        for instance in instances {
            if groups.isEmpty || instance.start == .onClick {
                groups.append([[instance]])
            } else if instance.start == .afterPrevious {
                groups[groups.count - 1].append([instance])
            } else {
                groups[groups.count - 1][groups[groups.count - 1].count - 1].append(instance)
            }
        }

        let mainSequence = takeID()
        xml.raw("<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"\(mainSequence)\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>")
        for (index, group) in groups.enumerated() {
            xml.raw("<p:par><p:cTn id=\"\(takeID())\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/>")
            if index == 0, group[0][0].start != .onClick {
                // Starts with the slide rather than on a click.
                xml.raw("<p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"\(mainSequence)\"/></p:cond>")
            }
            xml.raw("</p:stCondLst><p:childTnLst>")
            var offset = 0
            for step in group {
                xml.raw("<p:par><p:cTn id=\"\(takeID())\" fill=\"hold\"><p:stCondLst><p:cond delay=\"\(offset)\"/></p:stCondLst><p:childTnLst>")
                for instance in step { effect(instance) }
                xml.raw("</p:childTnLst></p:cTn></p:par>")
                offset = min(offset + (step.map { $0.delay + $0.length }.max() ?? 0), 2_000_000_000)
            }
            xml.raw("</p:childTnLst></p:cTn></p:par>")
        }
        xml.raw("</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>")
        xml.raw("<p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>")
    }

    /// One effect node, with its behaviors as PowerPoint's preset defines them.
    private mutating func effect(_ instance: Instance) {
        guard let animation = instance.animation else {
            play(instance)
            return
        }
        let effect = animation.effect
        let preset = PPTXAnimationPresets.preset(effect)
        let nodeType = switch instance.start {
        case .onClick: "clickEffect"
        case .withPrevious: "withEffect"
        case .afterPrevious: "afterEffect"
        }
        xml.raw("<p:par><p:cTn id=\"\(takeID())\" presetID=\"\(preset.id)\" presetClass=\"\(preset.presetClass)\"")
        xml.raw(" presetSubtype=\"\(preset.subtype)\" fill=\"hold\"")
        if let groupID = instance.groupID { xml.raw(" grpId=\"\(groupID)\"") }
        xml.raw(" nodeType=\"\(nodeType)\"><p:stCondLst><p:cond delay=\"\(instance.delay)\"/></p:stCondLst><p:childTnLst>")
        var target = "<p:spTgt spid=\"\(instance.spid)\""
        target += instance.paragraph.map { "><p:txEl><p:pRg st=\"\($0)\" end=\"\($0)\"/></p:txEl></p:spTgt>" } ?? "/>"
        let duration = instance.duration
        switch effect {
        case .appear:
            setVisibility(true, at: 0, target: target)
        case .disappear:
            setVisibility(false, at: 0, target: target)
        case .fadeIn:
            setVisibility(true, at: 0, target: target)
            fade(in: true, duration: duration, target: target)
        case .fadeOut:
            fade(in: false, duration: duration, target: target)
            setVisibility(false, at: max(duration - 1, 0), target: target)
        case .flyInFromLeft, .flyInFromRight, .flyInFromBottom, .flyInFromTop:
            setVisibility(true, at: 0, target: target)
            fly(effect, entering: true, duration: duration, target: target)
        case .flyOutToLeft, .flyOutToRight, .flyOutToBottom, .flyOutToTop:
            fly(effect, entering: false, duration: duration, target: target)
            setVisibility(false, at: max(duration - 1, 0), target: target)
        case .zoomIn:
            setVisibility(true, at: 0, target: target)
            animate("ppt_w", from: "<p:fltVal val=\"0\"/>", to: "<p:strVal val=\"#ppt_w\"/>", additive: false, duration: duration, target: target)
            animate("ppt_h", from: "<p:fltVal val=\"0\"/>", to: "<p:strVal val=\"#ppt_h\"/>", additive: false, duration: duration, target: target)
            fade(in: true, duration: duration, target: target)
        case .zoomOut:
            animate("ppt_w", from: "<p:strVal val=\"#ppt_w\"/>", to: "<p:fltVal val=\"0\"/>", additive: false, duration: duration, target: target)
            animate("ppt_h", from: "<p:strVal val=\"#ppt_h\"/>", to: "<p:fltVal val=\"0\"/>", additive: false, duration: duration, target: target)
            fade(in: false, duration: duration, target: target)
            setVisibility(false, at: max(duration - 1, 0), target: target)
        case .spin:
            xml.raw("<p:animRot by=\"21600000\"><p:cBhvr><p:cTn id=\"\(takeID())\" dur=\"\(duration)\" fill=\"hold\"/><p:tgtEl>\(target)</p:tgtEl>")
            xml.raw("<p:attrNameLst><p:attrName>r</p:attrName></p:attrNameLst></p:cBhvr></p:animRot>")
        }
        xml.raw("</p:childTnLst></p:cTn></p:par>")
    }

    private mutating func setVisibility(_ visible: Bool, at delay: Int, target: String) {
        xml.raw("<p:set><p:cBhvr><p:cTn id=\"\(takeID())\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"\(delay)\"/></p:stCondLst></p:cTn>")
        xml.raw("<p:tgtEl>\(target)</p:tgtEl><p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr>")
        xml.raw("<p:to><p:strVal val=\"\(visible ? "visible" : "hidden")\"/></p:to></p:set>")
    }

    private mutating func fade(in entering: Bool, duration: Int, target: String) {
        xml.raw("<p:animEffect transition=\"\(entering ? "in" : "out")\" filter=\"fade\"><p:cBhvr><p:cTn id=\"\(takeID())\" dur=\"\(duration)\"/>")
        xml.raw("<p:tgtEl>\(target)</p:tgtEl></p:cBhvr></p:animEffect>")
    }

    /// Fly In moves from off the slide to the element's place; Fly Out the other way. Both animate x and y.
    private mutating func fly(_ effect: AnimationEffect, entering: Bool, duration: Int, target: String) {
        guard let edge = PPTXAnimationPresets.offSlide(effect) else { return }
        for attribute in ["ppt_x", "ppt_y"] {
            let place = "<p:strVal val=\"#\(attribute)\"/>"
            let away = attribute == edge.attribute ? "<p:strVal val=\"\(edge.value)\"/>" : place
            animate(attribute, from: entering ? away : place, to: entering ? place : away, additive: true, duration: duration, target: target)
        }
    }

    private mutating func animate(_ attribute: String, from: String, to: String, additive: Bool, duration: Int, target: String) {
        xml.raw("<p:anim calcmode=\"lin\" valueType=\"num\"><p:cBhvr\(additive ? " additive=\"base\"" : "")>")
        xml.raw("<p:cTn id=\"\(takeID())\" dur=\"\(duration)\" fill=\"hold\"/><p:tgtEl>\(target)</p:tgtEl>")
        xml.raw("<p:attrNameLst><p:attrName>\(attribute)</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst>")
        xml.raw("<p:tav tm=\"0\"><p:val>\(from)</p:val></p:tav><p:tav tm=\"100000\"><p:val>\(to)</p:val></p:tav></p:tavLst></p:anim>")
    }

    // MARK: Clips

    /// A clip's play command, PowerPoint's Play media effect (preset 1 of the media call class).
    private mutating func play(_ instance: Instance) {
        let nodeType = switch instance.start {
        case .onClick: "clickEffect"
        case .withPrevious: "withEffect"
        case .afterPrevious: "afterEffect"
        }
        xml.raw("<p:par><p:cTn id=\"\(takeID())\" presetID=\"1\" presetClass=\"mediacall\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"\(nodeType)\">")
        xml.raw("<p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:cmd type=\"call\" cmd=\"playFrom(0.0)\"><p:cBhvr>")
        xml.raw("<p:cTn id=\"\(takeID())\" dur=\"1\" fill=\"hold\"/><p:tgtEl><p:spTgt spid=\"\(instance.spid)\"/></p:tgtEl></p:cBhvr></p:cmd>")
        xml.raw("</p:childTnLst></p:cTn></p:par>")
    }

    /// The sequence a manually played clip's own click triggers, as PowerPoint writes it: the Pause media effect (preset
    /// 2), which plays the clip when it isn't playing and pauses it when it is.
    private mutating func trigger(_ clip: PPTXWrittenClip) {
        let target = "<p:tgtEl><p:spTgt spid=\"\(clip.spid)\"/></p:tgtEl>"
        xml.raw("<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"\(takeID())\" restart=\"whenNotActive\" fill=\"hold\" evtFilter=\"cancelBubble\"")
        xml.raw(" nodeType=\"interactiveSeq\"><p:stCondLst><p:cond evt=\"onClick\" delay=\"0\">\(target)</p:cond></p:stCondLst>")
        xml.raw("<p:endSync evt=\"end\" delay=\"0\"><p:rtn val=\"all\"/></p:endSync><p:childTnLst>")
        for _ in 0..<2 { xml.raw("<p:par><p:cTn id=\"\(takeID())\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>") }
        xml.raw("<p:par><p:cTn id=\"\(takeID())\" presetID=\"2\" presetClass=\"mediacall\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"clickEffect\">")
        xml.raw("<p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:cmd type=\"call\" cmd=\"togglePause\"><p:cBhvr>")
        xml.raw("<p:cTn id=\"\(takeID())\" dur=\"1\" fill=\"hold\"/>\(target)</p:cBhvr></p:cmd></p:childTnLst></p:cTn></p:par>")
        for _ in 0..<2 { xml.raw("</p:childTnLst></p:cTn></p:par>") }
        xml.raw("</p:childTnLst></p:cTn><p:nextCondLst><p:cond evt=\"onClick\" delay=\"0\">\(target)</p:cond></p:nextCondLst></p:seq>")
    }

    /// A clip's media node: its volume, mute, whether it shows while stopped, loop (repeating indefinitely) and, for a sound
    /// that plays across slides, 999 slides, ended by a stop-audio event.
    private mutating func mediaNode(_ written: PPTXWrittenClip) {
        let clip = written.clip
        let tag = clip.kind == .video ? "p:video" : "p:audio"
        let acrossSlides = clip.kind == .audio && !clip.stopsOnSlideChange
        xml.raw("<\(tag)><p:cMediaNode vol=\"\(PPTXValue.clamped(clip.volume * 100_000, 0...100_000, fallback: 100_000))\"")
        if clip.isMuted { xml.raw(" mute=\"1\"") }
        if acrossSlides { xml.raw(" numSld=\"999\"") }
        if clip.hidesWhenPresenting { xml.raw(" showWhenStopped=\"0\"") }
        xml.raw("><p:cTn id=\"\(takeID())\"")
        if clip.loops { xml.raw(" repeatCount=\"indefinite\"") }
        xml.raw(" fill=\"hold\" display=\"0\"><p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst>")
        if acrossSlides { xml.raw("<p:endCondLst><p:cond evt=\"onStopAudio\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:endCondLst>") }
        xml.raw("</p:cTn><p:tgtEl><p:spTgt spid=\"\(written.spid)\"/></p:tgtEl></p:cMediaNode></\(tag)>")
    }
}
