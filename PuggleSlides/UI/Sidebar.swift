import AppKit
import PuggleSlidesKit
import SwiftUI

/// The panels that open on the right of the canvas.
enum SidebarKind: Equatable {
    case themes, formatOptions, motion, chartEditor, themeColors, comments

    var title: String {
        switch self {
        case .themes: "Themes"
        case .formatOptions: "Format options"
        case .motion: "Motion"
        case .chartEditor: "Chart editor"
        case .themeColors: "Theme colors"
        case .comments: "Comments"
        }
    }
}

/// What the side panels ask their window to do.
protocol SidebarActions: CommentActions {
    var controller: PresentationController { get }
    func closeSidebar()
    func importTheme()
}

struct SidebarView: View {
    let state: EditorState
    let actions: SidebarActions

    var body: some View {
        if let kind = state.sidebar {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(kind.title).font(.system(size: 16)).foregroundStyle(Theme.primaryText)
                    Spacer()
                    ToolbarIconButton(symbol: "xmark", help: "Close") { actions.closeSidebar() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider()
                ScrollView {
                    Group {
                        switch kind {
                        case .themes: ThemesPanel(state: state, actions: actions)
                        case .formatOptions: FormatOptionsPanel(state: state, actions: actions)
                        case .motion: MotionPanel(state: state, actions: actions)
                        case .chartEditor: ChartEditorPanel(state: state, actions: actions)
                        case .themeColors: ThemeColorsPanel(state: state, actions: actions)
                        case .comments: CommentsPanel(state: state, actions: actions)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.divider).frame(width: 1) }
        }
    }
}

// MARK: Themes

/// Previews of each theme's title slide, drawn once.
@MainActor
enum ThemePreviews {
    private static var cache: [String: NSImage] = [:]

    static func image(for theme: SlideTheme, slideSize: SlideSize, width: CGFloat = 268) -> NSImage {
        let key = "\(theme.name)|\(theme.colors.colors.map { "\($0.key.rawValue)\($0.value.hex)" }.sorted())|\(theme.fonts.major)|\(slideSize.width)x\(slideSize.height)"
        if let image = cache[key] { return image }
        var presentation = Presentation(slideSize: slideSize, themes: [theme], defaultTextStyle: BuiltInThemes.defaultTextStyle)
        let layout = theme.layout(kind: .title) ?? theme.layouts.first
        if let layout {
            var slide = presentation.makeSlide(layoutID: layout.id)
            if let index = slide.elements.firstIndex(where: { $0.placeholder?.type.isTitle == true }) {
                slide.elements[index].shape?.text = TextBody(theme.name)
            }
            presentation.slides = [slide]
        }
        let height = width * slideSize.height / max(slideSize.width, 1)
        let image = presentation.slides.first.map { SlideRenderer.image(of: $0, in: presentation, size: CGSize(width: width, height: height)) }
            ?? NSImage(size: NSSize(width: width, height: height))
        cache[key] = image
        return image
    }
}

struct ThemesPanel: View {
    let state: EditorState
    let actions: SidebarActions

    private var controller: PresentationController { actions.controller }

    var body: some View {
        let _ = state.revision
        let size = controller.presentation.slideSize
        let current = controller.currentSlide.map { controller.presentation.theme(for: $0) } ?? controller.presentation.themes.first
        VStack(alignment: .leading, spacing: 14) {
            if let current {
                Text("In this presentation").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                preview(current, size: size, isCurrent: true) {}
            }
            Text("Themes").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText).padding(.top, 6)
            ForEach(BuiltInThemes.designs, id: \.name) { design in
                let theme = BuiltInThemes.make(design, slideSize: size)
                preview(theme, size: size, isCurrent: false) {
                    controller.applyTheme(BuiltInThemes.make(design, slideSize: size))
                }
            }
            PanelButton(title: "Import theme", primary: false) { actions.importTheme() }
                .padding(.top, 4)
        }
    }

    private func preview(_ theme: SlideTheme, size: SlideSize, isCurrent: Bool, apply: @escaping () -> Void) -> some View {
        Button(action: apply) {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: ThemePreviews.image(for: theme, slideSize: size))
                    .resizable()
                    .aspectRatio(CGFloat(size.width / max(size.height, 1)), contentMode: .fit)
                    .overlay(Rectangle().stroke(isCurrent ? Theme.accent : Color(nsColor: Theme.slideBorder), lineWidth: isCurrent ? 2 : 1))
                Text(theme.name).font(.system(size: 13)).foregroundStyle(Theme.primaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCurrent ? theme.name : "Apply the \(theme.name) theme")
    }
}

// MARK: Format options

struct FormatOptionsPanel: View {
    let state: EditorState
    let actions: SidebarActions
    @State private var width = ""
    @State private var height = ""
    @State private var x = ""
    @State private var y = ""
    @State private var angle = ""
    @State private var lockAspect = false
    @State private var padding = ["", "", "", ""]

    private var controller: PresentationController { actions.controller }

    private var element: SlideElement? {
        controller.selectedElements.count == 1 ? controller.selectedElements.first : nil
    }

    var body: some View {
        let _ = state.revision
        VStack(alignment: .leading, spacing: 4) {
            if let element {
                let placement = controller.placement(of: element)
                PanelSection(title: "Size & Rotation") {
                    HStack(spacing: 10) {
                        labeled("Width") { inchField($width) { commitSize(width: $0, height: nil) } }
                        labeled("Height") { inchField($height) { commitSize(width: nil, height: $0) } }
                    }
                    Toggle("Lock aspect ratio", isOn: $lockAspect).font(.system(size: 13))
                    HStack(spacing: 10) {
                        labeled("Rotate") {
                            PanelField(placeholder: "0°", text: $angle).frame(width: 70).onSubmit { commitAngle() }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(" ").font(.system(size: 11))
                            HStack(spacing: 2) {
                                ToolbarIconButton(symbol: "rotate.left", help: "Rotate counter-clockwise 90°") { controller.rotateSelection(by: -90) }
                                ToolbarIconButton(symbol: "rotate.right", help: "Rotate clockwise 90°") { controller.rotateSelection(by: 90) }
                                ToolbarIconButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Flip horizontally") {
                                    controller.flipSelection(horizontal: true)
                                }
                                ToolbarIconButton(symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", help: "Flip vertically") {
                                    controller.flipSelection(horizontal: false)
                                }
                            }
                        }
                    }
                }
                PanelSection(title: "Position") {
                    HStack(spacing: 10) {
                        labeled("X") { inchField($x) { commitPosition(x: $0, y: nil) } }
                        labeled("Y") { inchField($y) { commitPosition(x: nil, y: $0) } }
                    }
                    Text("From the top left corner").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                if element.picture != nil {
                    ImageOptionsSections(element: element, controller: controller)
                }
                if let clip = element.media {
                    MediaPlaybackSections(element: element, clip: clip, controller: controller)
                }
                if element.shape != nil, !element.isLine, !element.isWordArt {
                    let style = controller.style(of: element)
                    PanelSection(title: "Text fitting") {
                        ForEach(Autofit.allCases, id: \.self) { option in
                            Button {
                                controller.setAutofit(option)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: style?.bodyProperties.autofit == option ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(style?.bodyProperties.autofit == option ? Theme.accent : Theme.secondaryText)
                                    Text(option.title).font(.system(size: 13)).foregroundStyle(Theme.primaryText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Indentation padding").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.top, 6)
                        HStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { index in
                                labeled(["Top", "Bottom", "Left", "Right"][index]) {
                                    PanelField(placeholder: "0\"", text: $padding[index]).frame(width: 56).onSubmit { commitPadding() }
                                }
                            }
                        }
                    }
                }
                let _ = placement
            } else {
                Text(controller.selectedElements.isEmpty ? "Select an object to change its size, position and text fitting."
                     : "Select a single object to change its size, position and text fitting.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: state.revision) { _, _ in reload() }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    private func inchField(_ text: Binding<String>, commit: @escaping (Double) -> Void) -> some View {
        PanelField(placeholder: "0 in", text: text)
            .frame(width: 90)
            .onSubmit {
                let cleaned = text.wrappedValue.replacingOccurrences(of: "in", with: "").replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let value = Double(cleaned) { commit(value * 72) }
                reload()
            }
    }

    private static func inches(_ points: Double) -> String {
        String(format: "%.2f in", points / 72)
    }

    private func reload() {
        guard let element else { return }
        let placement = controller.placement(of: element)
        width = Self.inches(abs(placement.frame.width))
        height = Self.inches(abs(placement.frame.height))
        x = Self.inches(placement.frame.x)
        y = Self.inches(placement.frame.y)
        angle = String(format: "%g°", (placement.rotation * 10).rounded() / 10)
        if let insets = controller.style(of: element)?.bodyProperties.insets {
            padding = [insets.top, insets.bottom, insets.left, insets.right].map { String(format: "%.2f\"", $0 / 72) }
        }
    }

    private func commitSize(width: Double?, height: Double?) {
        guard let element else { return }
        var placement = controller.placement(of: element)
        let frame = placement.frame
        var newWidth = width ?? frame.width, newHeight = height ?? frame.height
        if lockAspect, frame.width > 0, frame.height > 0 {
            if width != nil { newHeight = frame.height * newWidth / frame.width } else { newWidth = frame.width * newHeight / frame.height }
        }
        placement.frame = SlideRect(x: frame.midX - newWidth / 2, y: frame.midY - newHeight / 2, width: max(1, newWidth), height: max(1, newHeight))
        controller.setPlacements([element.id: placement], actionName: "Resize")
    }

    private func commitPosition(x: Double?, y: Double?) {
        guard let element else { return }
        var placement = controller.placement(of: element)
        placement.frame = placement.frame.offsetBy(dx: (x ?? placement.frame.x) - placement.frame.x, dy: (y ?? placement.frame.y) - placement.frame.y)
        controller.setPlacements([element.id: placement], actionName: "Move")
    }

    private func commitAngle() {
        guard let element, let value = Double(angle.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)) else {
            reload()
            return
        }
        var placement = controller.placement(of: element)
        placement.rotation = Placement.normalized(value)
        controller.setPlacements([element.id: placement], actionName: "Rotate")
    }

    private func commitPadding() {
        let values = padding.map { Double($0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "in", with: "").trimmingCharacters(in: .whitespaces)) }
        guard values.allSatisfy({ $0 != nil }) else { return reload() }
        let points = values.map { max(0, $0! * 72) }
        controller.setInsets(TextInsets(left: points[2], top: points[0], right: points[3], bottom: points[1]))
    }
}

// MARK: Shared pieces

/// A labelled section of a panel.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primaryText)
            content()
        }
        .padding(.bottom, 16)
    }
}

/// A text field styled for the side panels.
struct PanelField: View {
    let placeholder: String
    @Binding var text: String
    var isValid = true

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isValid ? Theme.divider : Color.red, lineWidth: 1))
    }
}

/// A primary button for the side panels, such as "Done".
struct PanelButton: View {
    let title: String
    var primary = true
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primary ? Color.white : Theme.accent)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(Capsule().fill(primary ? Theme.accent : Color.clear))
                .overlay(Capsule().strokeBorder(primary ? Color.clear : Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The theme builder's Colors: the theme's twelve colors, each changed everywhere it's used.
struct ThemeColorsPanel: View {
    let state: EditorState
    let actions: SidebarActions

    private var controller: PresentationController { actions.controller }

    var body: some View {
        let _ = state.revision
        let colors = controller.presentation.themes.first?.colors
        VStack(alignment: .leading, spacing: 10) {
            if controller.isThemeBuilderOpen, let colors {
                Text("Choose a theme color to change it. Text, shapes and charts that use it change too.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                ForEach(ThemeColorSlot.allCases, id: \.self) { slot in
                    HStack {
                        Text(slot.title).font(.system(size: 13))
                        Spacer()
                        ColorPicker("", selection: Binding(get: { Self.color(colors[slot]) }, set: { color in
                            if let rgb = Self.rgb(color) { controller.setBuilderThemeColor(slot, to: rgb) }
                        }), supportsOpacity: false)
                        .labelsHidden()
                    }
                }
            } else {
                Text("Open the theme builder (Slide ▸ Edit theme) to change the theme's colors.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    static func color(_ rgb: RGBColor) -> Color {
        Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    static func rgb(_ color: Color) -> RGBColor? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return RGBColor(unitRed: Double(srgb.redComponent), unitGreen: Double(srgb.greenComponent), unitBlue: Double(srgb.blueComponent))
    }
}
