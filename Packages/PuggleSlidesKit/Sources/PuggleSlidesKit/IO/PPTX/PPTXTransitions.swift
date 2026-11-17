import Foundation

/// Slide transitions as PowerPoint writes them: an `mc:AlternateContent` whose PowerPoint 2010 (p14) choice holds
/// the exact duration and the 2010 transitions, with a classic fallback for older readers.
enum PPTXTransitions {
    static let markupCompatibility = "http://schemas.openxmlformats.org/markup-compatibility/2006"
    static let powerPoint2010 = "http://schemas.microsoft.com/office/powerpoint/2010/main"

    // MARK: Writing

    /// The element for a transition kind, in the p14 choice and in the fallback (where PowerPoint uses a fade for
    /// the 2010 transitions). Push's `dir` is the direction the slides move: "l" brings the new slide in from the right.
    static func elements(_ kind: TransitionKind) -> (choice: String, fallback: String) {
        switch kind {
        case .none: ("", "")
        case .dissolve: ("<p:dissolve/>", "<p:dissolve/>")
        case .fade: ("<p:fade/>", "<p:fade/>")
        case .slideFromRight: ("<p:push dir=\"l\"/>", "<p:push dir=\"l\"/>")
        case .slideFromLeft: ("<p:push dir=\"r\"/>", "<p:push dir=\"r\"/>")
        case .flip: ("<p14:flip dir=\"r\"/>", "<p:fade/>")
        case .cube: ("<p14:prism/>", "<p:fade/>")
        case .gallery: ("<p14:gallery dir=\"l\"/>", "<p:fade/>")
        }
    }

    /// PowerPoint's speeds before durations: fast is 0.5 s, medium 0.75 s, slow 1 s.
    static func speed(_ seconds: Double) -> String {
        seconds < 0.625 ? "fast" : seconds < 0.875 ? "med" : "slow"
    }

    static func write(_ transition: SlideTransition, into xml: inout XMLWriter) {
        let (choice, fallback) = elements(transition.kind)
        let milliseconds = PPTXValue.clamped(transition.duration * 1000, 0...86_400_000)
        let speed = speed(transition.duration)
        xml.raw("<mc:AlternateContent xmlns:mc=\"\(markupCompatibility)\"><mc:Choice xmlns:p14=\"\(powerPoint2010)\" Requires=\"p14\">")
        xml.raw("<p:transition spd=\"\(speed)\" p14:dur=\"\(milliseconds)\"")
        xml.raw(choice.isEmpty ? "/>" : ">\(choice)</p:transition>")
        xml.raw("</mc:Choice><mc:Fallback><p:transition spd=\"\(speed)\"")
        xml.raw(fallback.isEmpty ? "/>" : ">\(fallback)</p:transition>")
        xml.raw("</mc:Fallback></mc:AlternateContent>")
    }

    // MARK: Reading

    /// The transition a slide (or layout) states, mapped to the nearest supported transition, and whether
    /// anything about it can't be kept: sounds and automatic advance timings.
    static func read(_ root: XNode) -> (transition: SlideTransition?, hasUnsupported: Bool) {
        guard let node = transitionNode(root) else { return (nil, false) }
        var unsupported = false
        if node["advTm"] != nil || PPTXValue.bool(node["advClick"]) == false { unsupported = true }
        if node.child("sndAc")?.child("stSnd") != nil { unsupported = true }

        var seconds: Double
        if let milliseconds = PPTXValue.double(node["dur"]), milliseconds >= 0 {
            seconds = milliseconds / 1000
        } else {
            switch node["spd"] {
            case "slow": seconds = 1
            case "med": seconds = 0.75
            default: seconds = 0.5
            }
        }
        seconds = min(seconds, 86_400)
        let effect = node.children.first { $0.name != "sndAc" && $0.name != "extLst" }
        return (SlideTransition(kind: effect.map(kind) ?? TransitionKind.none, duration: seconds), unsupported)
    }

    /// `p:transition` itself, or the one in an `mc:AlternateContent`: the first choice that has one (it carries
    /// the exact duration and newer effects), else the fallback.
    private static func transitionNode(_ root: XNode) -> XNode? {
        for child in root.children {
            if child.name == "transition" { return child }
            guard child.name == "AlternateContent" else { continue }
            for choice in child.children("Choice") {
                if let transition = choice.child("transition") { return transition }
            }
            if let transition = child.child("Fallback")?.child("transition") { return transition }
        }
        return nil
    }

    /// The nearest supported transition to a PowerPoint one. Directional ones slide from the side they come from.
    static func kind(_ node: XNode) -> TransitionKind {
        func horizontal(_ direction: String?) -> TransitionKind {
            // The direction the slides move: rightward means the new slide comes from the left.
            switch direction {
            case "r", "ru", "rd": .slideFromLeft
            default: .slideFromRight
            }
        }
        switch node.name {
        case "cut": return TransitionKind.none
        case "dissolve", "randomBar", "checker", "blinds", "comb", "strips", "vortex", "ripple", "honeycomb", "glitter", "shred":
            return .dissolve
        case "push", "cover", "pull", "wipe", "conveyor", "ferris", "pan": return horizontal(node["dir"])
        case "flip", "switch": return .flip
        case "prism", "doors", "window": return .cube
        case "gallery": return .gallery
        case "prstTrans":
            let preset = node["prst"] ?? ""
            return preset.hasPrefix("pageCurl") || preset == "peelOff" ? .flip : .fade
        default:
            // fade, random, split, circle, diamond, plus, wedge, wheel, zoom, newsflash, reveal, flash, warp,
            // flythrough, wheelReverse, morph and anything newer.
            return .fade
        }
    }
}
