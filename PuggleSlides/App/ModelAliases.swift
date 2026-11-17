import PuggleSlidesKit

/// AppKit brings in QuickDraw's `RGBColor` and `Picture` too; inside the app the names always mean the model's.
typealias RGBColor = PuggleSlidesKit.RGBColor
typealias Picture = PuggleSlidesKit.Picture
/// The model's theme, layout and shape, beside the app's `Theme` colors and SwiftUI's `Layout` and `Shape`.
typealias SlideTheme = PuggleSlidesKit.Theme
typealias SlideLayout = PuggleSlidesKit.Layout
typealias SlideShape = PuggleSlidesKit.Shape
/// SwiftUI has a `SlideTransition` too; the app only ever means the model's.
typealias SlideTransition = PuggleSlidesKit.SlideTransition
