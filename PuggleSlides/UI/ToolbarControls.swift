import AppKit
import PuggleSlidesKit
import SwiftUI

/// Holds the AppKit view behind a SwiftUI control so native menus can pop up beneath it.
final class AnchorHolder {
    weak var view: NSView?
}

struct AnchorView: NSViewRepresentable {
    let holder: AnchorHolder

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = FlippedView()
        holder.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        holder.view = nsView
    }
}

/// Background that lets the header drag the window, like a title bar.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct HoverBackground: ViewModifier {
    var isOn = false
    var cornerRadius: CGFloat = 4
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(isOn ? Theme.activeFill : (hovering ? Theme.hoverFill : .clear)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverBackground(isOn: Bool = false, cornerRadius: CGFloat = 4) -> some View {
        modifier(HoverBackground(isOn: isOn, cornerRadius: cornerRadius))
    }
}

struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    var isOn = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isOn ? Theme.accent : Theme.secondaryText)
                .frame(width: 28, height: 28)
                .hoverBackground(isOn: isOn)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A toolbar control that opens a native menu beneath itself.
struct ToolbarDropdown<Label: View>: View {
    let help: String
    var showsChevron = true
    var isEnabled = true
    let open: (NSView?) -> Void
    @ViewBuilder let label: () -> Label
    @State private var anchor = AnchorHolder()

    var body: some View {
        Button {
            open(anchor.view)
        } label: {
            HStack(spacing: 3) {
                label()
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 28)
            .hoverBackground()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .background(AnchorView(holder: anchor))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Icon button with a separate chevron for its presets (lists).
struct SplitToolbarButton: View {
    let symbol: String
    let help: String
    var isOn = false
    var isEnabled = true
    let action: () -> Void
    let openPresets: (NSView?) -> Void
    @State private var anchor = AnchorHolder()

    var body: some View {
        HStack(spacing: 0) {
            ToolbarIconButton(symbol: symbol, help: help, isOn: isOn, isEnabled: isEnabled, action: action)
            Button {
                openPresets(anchor.view)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 12, height: 28)
                    .hoverBackground()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.38)
            .help("\(help) menu")
            .accessibilityLabel("\(help) menu")
        }
        .background(AnchorView(holder: anchor))
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

/// The fill color icon: a tipped paint bucket with a drop.
nonisolated struct PaintBucketShape: SwiftUI.Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        path.move(to: point(16.56, 8.94))
        path.addLine(to: point(7.62, 0))
        path.addLine(to: point(6.21, 1.41))
        path.addLine(to: point(8.59, 3.79))
        path.addLine(to: point(3.44, 8.94))
        path.addQuadCurve(to: point(3.44, 11.06), control: point(2.85, 10))
        path.addLine(to: point(8.94, 16.56))
        path.addQuadCurve(to: point(11.06, 16.56), control: point(10, 17.15))
        path.addLine(to: point(16.56, 11.06))
        path.addQuadCurve(to: point(16.56, 8.94), control: point(17.15, 10))
        path.closeSubpath()
        path.move(to: point(5.21, 10))
        path.addLine(to: point(10, 5.21))
        path.addLine(to: point(14.79, 10))
        path.closeSubpath()
        path.move(to: point(19, 11.5))
        path.addCurve(to: point(17, 15), control1: point(19, 11.5), control2: point(17, 13.67))
        path.addCurve(to: point(19, 17), control1: point(17, 16.1), control2: point(17.9, 17))
        path.addCurve(to: point(21, 15), control1: point(20.1, 17), control2: point(21, 16.1))
        path.addCurve(to: point(19, 11.5), control1: point(21, 13.67), control2: point(19, 11.5))
        path.closeSubpath()
        return path
    }
}

/// "A" with a color bar (text color) or a paint bucket with a color bar (fill color).
struct ColorToolbarButton: View {
    let isFill: Bool
    let currentHex: String?
    var isEnabled = true
    let pick: (NSColor?) -> Void
    let custom: () -> Void
    @State private var showingPalette = false

    var body: some View {
        Button {
            showingPalette = true
        } label: {
            VStack(spacing: 1) {
                if isFill {
                    PaintBucketShape().fill(style: FillStyle(eoFill: true)).frame(width: 15, height: 15)
                } else {
                    Text("A").font(.system(size: 15, weight: .medium, design: .serif))
                }
                Rectangle()
                    .fill(Color(nsColor: currentHex.flatMap(NSColor.init(hex:)) ?? (isFill ? .clear : .black)))
                    .frame(width: 16, height: 3.5)
                    .overlay(Rectangle().stroke(Color.black.opacity(currentHex == nil && isFill ? 0.25 : 0), lineWidth: 0.5))
            }
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 28, height: 28)
            .hoverBackground(isOn: showingPalette)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .help(isFill ? "Fill color" : "Text color")
        .accessibilityLabel(isFill ? "Fill color" : "Text color")
        .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
            ColorPaletteView(selectedHex: currentHex) { color in
                showingPalette = false
                pick(color)
            } custom: {
                showingPalette = false
                custom()
            }
        }
    }
}

struct ColorPaletteView: View {
    let selectedHex: String?
    let pick: (NSColor?) -> Void
    let custom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                pick(nil)
            } label: {
                Label("Reset", systemImage: "drop.halffull")
                    .font(.system(size: 13))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .hoverBackground()
            }
            .buttonStyle(.plain)
            swatchRow(ColorPalette.grayRow)
            swatchRow(ColorPalette.brightRow)
            VStack(spacing: 4) {
                ForEach(Array(ColorPalette.shadeRows.enumerated()), id: \.offset) { _, row in swatchRow(row) }
            }
            Divider()
            HStack {
                Text("CUSTOM").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button(action: custom) {
                    Image(systemName: "plus.circle").font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Choose a custom color")
            }
        }
        .padding(12)
        .frame(width: 252)
    }

    private func swatchRow(_ swatches: [ColorPalette.Swatch]) -> some View {
        HStack(spacing: 4) {
            ForEach(swatches) { swatch in
                Button {
                    pick(swatch.color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: swatch.color))
                        .overlay(Circle().stroke(Color.black.opacity(swatch.hex == "FFFFFF" || swatch.hex.hasPrefix("F") ? 0.2 : 0), lineWidth: 0.5))
                        .overlay {
                            if swatch.hex == selectedHex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isLight(swatch.color) ? Color.black : Color.white)
                            }
                        }
                        .frame(width: 19, height: 19)
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }
        }
    }

    private func isLight(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        return rgb.redComponent * 0.299 + rgb.greenComponent * 0.587 + rgb.blueComponent * 0.114 > 0.6
    }
}

struct FontSizeControl: View {
    let size: CGFloat?
    var isEnabled = true
    let set: (CGFloat) -> Void
    let step: (CGFloat) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var formatted: String {
        guard let size else { return "" }
        return size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)
    }

    var body: some View {
        HStack(spacing: 1) {
            ToolbarIconButton(symbol: "minus", help: "Decrease font size", isEnabled: isEnabled) { step(-1) }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .frame(width: 34, height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(focused ? 1 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(focused ? Theme.accent : Theme.secondaryText.opacity(0.6), lineWidth: focused ? 1.5 : 1))
                .focused($focused)
                .disabled(!isEnabled)
                .onSubmit {
                    if let value = Double(text.trimmingCharacters(in: .whitespaces)), value > 0 { set(CGFloat(value)) }
                    text = formatted
                }
                .help("Font size")
                .accessibilityLabel("Font size")
            ToolbarIconButton(symbol: "plus", help: "Increase font size", isEnabled: isEnabled) { step(1) }
        }
        .onAppear { text = formatted }
        .onChange(of: size) { _, _ in if !focused { text = formatted } }
        .onChange(of: focused) { _, isFocused in if !isFocused { text = formatted } }
    }
}
