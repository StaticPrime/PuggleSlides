import AppKit
import SwiftUI

/// Colors and metrics for the window chrome. Slides draw with their own theme's colors.
nonisolated enum Theme {
    static let canvas = NSColor(srgbRed: 0xF9 / 255, green: 0xFB / 255, blue: 0xFD / 255, alpha: 1)
    static let toolbarFill = Color(red: 0xED / 255, green: 0xF2 / 255, blue: 0xFA / 255)
    static let primaryText = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)
    static let secondaryText = Color(red: 0x44 / 255, green: 0x47 / 255, blue: 0x46 / 255)
    static let hoverFill = Color.black.opacity(0.07)
    static let activeFill = Color(red: 0xD3 / 255, green: 0xE3 / 255, blue: 0xFD / 255)
    static let accent = Color(red: 0x0B / 255, green: 0x57 / 255, blue: 0xD0 / 255)
    static let divider = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xC7 / 255)
    static let bannerFill = Color(red: 0xFE / 255, green: 0xF7 / 255, blue: 0xE0 / 255)

    /// Selection outlines and resize handles on the canvas.
    static let selection = NSColor(srgbRed: 0x1A / 255, green: 0x73 / 255, blue: 0xE8 / 255, alpha: 1)
    /// The yellow diamonds that adjust a shape (corner radius, arrow head…).
    static let adjustHandle = NSColor(srgbRed: 0xFB / 255, green: 0xBC / 255, blue: 0x04 / 255, alpha: 1)
    /// The red lines objects snap to while they move, and guides without a color of their own.
    static let snapLine = NSColor(srgbRed: 0xEA / 255, green: 0x43 / 255, blue: 0x35 / 255, alpha: 1)
    static let customGuide = NSColor(srgbRed: 0xF2 / 255, green: 0x8B / 255, blue: 0x82 / 255, alpha: 1)
    /// Selected table cells.
    static let cellSelection = NSColor(srgbRed: 0x1A / 255, green: 0x73 / 255, blue: 0xE8 / 255, alpha: 0.18)
    /// Outlines of empty placeholders and the shape under the pointer.
    static let placeholderOutline = NSColor(srgbRed: 0xBD / 255, green: 0xC1 / 255, blue: 0xC6 / 255, alpha: 1)
    static let promptText = NSColor(srgbRed: 0x80 / 255, green: 0x86 / 255, blue: 0x8B / 255, alpha: 1)
    /// The border around the slide on the canvas and around thumbnails.
    static let slideBorder = NSColor(srgbRed: 0xDA / 255, green: 0xDC / 255, blue: 0xE0 / 255, alpha: 1)
    /// The filmstrip's selected slide.
    static let filmstripSelection = NSColor(srgbRed: 0x0B / 255, green: 0x57 / 255, blue: 0xD0 / 255, alpha: 1)
    static let filmstripNumber = NSColor(srgbRed: 0x44 / 255, green: 0x47 / 255, blue: 0x46 / 255, alpha: 1)
    /// Alignment guides while dragging.
    static let guide = NSColor(srgbRed: 0xEA / 255, green: 0x43 / 255, blue: 0x35 / 255, alpha: 1)

    /// "100%" zoom shows a slide at the size a browser does: 96 pixels per inch rather than 72.
    static let baseMagnification: CGFloat = 96.0 / 72.0
    /// The zoom choices; "Fit" is separate.
    static let zoomLevels: [CGFloat] = [0.5, 1.0, 2.0]
    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 4.0
}
