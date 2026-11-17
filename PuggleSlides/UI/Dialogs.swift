import PuggleSlidesKit
import SwiftUI

/// Help ▸ Keyboard shortcuts: the Mac shortcuts PuggleSlides supports.
struct ShortcutsView: View {
    let dismiss: () -> Void

    private let columns: [[(String, [(String, String)])]] = [
        [
            ("Common actions", [
                ("New slide", "⌃M"),
                ("Duplicate", "⌘D"),
                ("Undo / redo", "⌘Z / ⇧⌘Z"),
                ("Cut / copy / paste", "⌘X / ⌘C / ⌘V"),
                ("Paste without formatting", "⇧⌘V"),
                ("Insert or edit link", "⌘K"),
                ("Select all / delete", "⌘A / Delete"),
                ("Alt text", "⌥⌘Y"),
            ]),
            ("Filmstrip", [
                ("Previous / next slide", "↑ / ↓"),
                ("Select previous / next slide too", "⇧↑ / ⇧↓"),
                ("Move slide up / down", "⌘↑ / ⌘↓"),
                ("Move slide to beginning / end", "⇧⌘↑ / ⇧⌘↓"),
            ]),
            ("Moving around", [
                ("Move to filmstrip", "⌥⇧⌘F"),
                ("Move to slide", "⌥⇧⌘C"),
                ("Move to speaker notes", "⌥⇧⌘S"),
            ]),
            ("Presenting", [
                ("Present / from the beginning", "⌘↩ / ⇧⌘↩"),
                ("Next / previous", "→ / ←"),
                ("Go to slide", "Number, then ↩"),
                ("First / last slide", "Home / End"),
                ("Black / white screen", "B / W"),
                ("Stop presenting", "Esc"),
            ]),
        ],
        [
            ("Text", [
                ("Bold / italic / underline", "⌘B / ⌘I / ⌘U"),
                ("Strikethrough", "⇧⌘X"),
                ("Superscript / subscript", "⌘. / ⌘,"),
                ("Bigger / smaller text", "⇧⌘. / ⇧⌘,"),
                ("Align left / center / right", "⇧⌘L / ⇧⌘E / ⇧⌘R"),
                ("Justify", "⇧⌘J"),
                ("Numbered / bulleted list", "⇧⌘7 / ⇧⌘8"),
                ("Increase / decrease indent", "⌘] / ⌘["),
                ("Clear formatting", "⌘\\"),
            ]),
            ("Objects", [
                ("Nudge / nudge further", "Arrows / ⇧ arrows"),
                ("Rotate 15° / 1°", "⌥← ⌥→ / ⌥⇧← ⌥⇧→"),
                ("Bring forward / send backward", "⌘↑ / ⌘↓"),
                ("Bring to front / send to back", "⇧⌘↑ / ⇧⌘↓"),
                ("Group / ungroup", "⌥⌘G / ⌥⇧⌘G"),
                ("Next / previous shape", "Tab / ⇧Tab"),
                ("Constrain while moving or resizing", "⇧ drag"),
                ("Duplicate while moving", "⌥ drag"),
                ("Zoom in / out / 100%", "⌘= / ⌘- / ⌘0"),
            ]),
            ("Comments and find", [
                ("Insert comment", "⌥⌘M"),
                ("Open comment history", "⌥⇧⌘A"),
                ("Show or hide comments", "⌥⇧⌘J"),
                ("Find / find and replace", "⌘F / ⇧⌘H"),
                ("Find again / previous", "⌘G / ⇧⌘G"),
            ]),
        ],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard shortcuts").font(.system(size: 20))
            HStack(alignment: .top, spacing: 36) {
                ForEach(0..<columns.count, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(0..<columns[column].count, id: \.self) { index in
                            let group = columns[column][index]
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                                ForEach(0..<group.1.count, id: \.self) { row in
                                    HStack {
                                        Text(group.1[row].0).font(.system(size: 13))
                                        Spacer(minLength: 16)
                                        Text(group.1[row].1).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 350)
                }
            }
            HStack {
                Spacer()
                Button("Close", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .fixedSize()
    }
}

/// Slide ▸ Change background: a color or an image, reset to the theme's, or added to the theme.
struct BackgroundView: View {
    let themeColors: [(ThemeColorSlot, RGBColor)]
    let currentHex: String?
    let setColor: (ColorRef?) -> Void
    let chooseImage: () -> Void
    let reset: () -> Void
    let addToTheme: () -> Void
    let dismiss: () -> Void
    @State private var showingPalette = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Background").font(.system(size: 20))
            HStack(spacing: 12) {
                Text("Color").font(.system(size: 13)).frame(width: 60, alignment: .leading)
                Button {
                    showingPalette = true
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: currentHex.flatMap(NSColor.init(hex:)) ?? .white))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                            .frame(width: 18, height: 18)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
                    SlideColorPalette(selectedHex: currentHex, themeColors: themeColors, allowsTransparent: true) { color in
                        showingPalette = false
                        setColor(color)
                    } custom: {
                        showingPalette = false
                    }
                }
            }
            HStack(spacing: 12) {
                Text("Image").font(.system(size: 13)).frame(width: 60, alignment: .leading)
                PanelButton(title: "Choose image", primary: false, action: chooseImage)
            }
            HStack(spacing: 12) {
                PanelButton(title: "Reset to theme", primary: false, action: reset)
                PanelButton(title: "Add to theme", primary: false, action: addToTheme)
                Spacer()
                PanelButton(title: "Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// File ▸ Page setup.
struct PageSetupView: View {
    let current: SlideSize
    let apply: (SlideSize) -> Void
    let dismiss: () -> Void
    @State private var choice = 0
    @State private var width = "10"
    @State private var height = "5.625"

    private static let presets: [(String, SlideSize)] = [("Widescreen 16:9", .widescreen), ("Widescreen 16:10", .widescreen16x10),
                                                         ("Standard 4:3", .standard)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Page setup").font(.system(size: 20))
            Picker("", selection: $choice) {
                ForEach(0..<Self.presets.count, id: \.self) { index in Text(Self.presets[index].0).tag(index) }
                Text("Custom").tag(Self.presets.count)
            }
            .labelsHidden()
            .frame(width: 220)
            if choice == Self.presets.count {
                HStack(spacing: 8) {
                    PanelField(placeholder: "Width", text: $width).frame(width: 80)
                    Text("×")
                    PanelField(placeholder: "Height", text: $height).frame(width: 80)
                    Text("inches").foregroundStyle(Theme.secondaryText)
                }
            }
            HStack {
                Spacer()
                PanelButton(title: "Cancel", primary: false, action: dismiss)
                PanelButton(title: "Apply") {
                    if choice < Self.presets.count {
                        apply(Self.presets[choice].1)
                    } else if let w = Double(width), let h = Double(height), w > 0, h > 0, w <= 200, h <= 200 {
                        apply(SlideSize(width: w * 72, height: h * 72))
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            choice = Self.presets.firstIndex { $0.1 == current } ?? Self.presets.count
            width = String(format: "%g", current.width / 72)
            height = String(format: "%g", current.height / 72)
        }
    }
}

/// Insert ▸ Slide numbers.
struct SlideNumbersView: View {
    let apply: (_ on: Bool, _ skipTitles: Bool, _ selectedOnly: Bool) -> Void
    let dismiss: () -> Void
    @State private var on = true
    @State private var skipTitles = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Slide numbers").font(.system(size: 20))
            Picker("", selection: $on) {
                Text("On").tag(true)
                Text("Off").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Toggle("Skip title slides", isOn: $skipTitles).disabled(!on)
            HStack {
                Spacer()
                PanelButton(title: "Cancel", primary: false, action: dismiss)
                PanelButton(title: "Apply to selected", primary: false) { apply(on, skipTitles, true); dismiss() }
                PanelButton(title: "Apply") { apply(on, skipTitles, false); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// Insert ▸ Link: a web address or another slide.
struct LinkEditorView: View {
    let slides: [(id: UUID, title: String)]
    let current: Hyperlink?
    let apply: (Hyperlink?) -> Void
    let dismiss: () -> Void
    @State private var address = ""
    @State private var slideID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link").font(.system(size: 20))
            PanelField(placeholder: "Search or paste a link", text: $address)
            Text("Slides in this presentation").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(slides, id: \.id) { slide in
                        Button {
                            slideID = slide.id
                            address = ""
                        } label: {
                            Text(slide.title).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4).padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 4).fill(slideID == slide.id ? Theme.activeFill : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 150)
            HStack {
                if current != nil { PanelButton(title: "Remove link", primary: false) { apply(nil); dismiss() } }
                Spacer()
                PanelButton(title: "Cancel", primary: false, action: dismiss)
                PanelButton(title: "Apply", isEnabled: !address.trimmingCharacters(in: .whitespaces).isEmpty || slideID != nil) {
                    let trimmed = address.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        let looksLikeEmail = trimmed.contains("@") && !trimmed.contains("/") && !trimmed.hasPrefix("mailto:")
                        let url = trimmed.contains("://") || trimmed.hasPrefix("mailto:") ? trimmed : (looksLikeEmail ? "mailto:" + trimmed : "https://" + trimmed)
                        apply(.url(url))
                    } else if let slideID {
                        apply(.slide(slideID))
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            switch current {
            case .url(let url)?: address = url
            case .slide(let id)?: slideID = id
            case nil: break
            }
        }
    }
}

/// Format ▸ Alt text.
struct AltTextView: View {
    @State var title: String
    @State var description: String
    let apply: (String, String) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alt text").font(.system(size: 20))
            Text("Alt text is read by screen readers to people who can't see the image or shape.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            Text("Description").font(.system(size: 12, weight: .medium))
            TextEditor(text: $description)
                .font(.system(size: 13))
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider))
            Text("Title").font(.system(size: 12, weight: .medium))
            PanelField(placeholder: "Title", text: $title)
            HStack {
                Spacer()
                PanelButton(title: "Cancel", primary: false, action: dismiss)
                PanelButton(title: "OK") { apply(title, description); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// Tools ▸ Preferences.
struct PreferencesView: View {
    let dismiss: () -> Void
    @AppStorage("PPSmartQuotes") private var smartQuotes = true
    @AppStorage("PPSmartDashes") private var smartDashes = true
    @AppStorage("PPSpellCheck") private var spellCheck = true
    @AppStorage("PPAutoCapitalize") private var capitalize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preferences").font(.system(size: 20))
            Toggle("Use smart quotes", isOn: $smartQuotes)
            Toggle("Use smart dashes", isOn: $smartDashes)
            Toggle("Automatically capitalize words", isOn: $capitalize)
            Toggle("Check spelling as you type", isOn: $spellCheck)
            HStack {
                Spacer()
                PanelButton(title: "OK", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(24)
        .frame(width: 360)
    }
}
