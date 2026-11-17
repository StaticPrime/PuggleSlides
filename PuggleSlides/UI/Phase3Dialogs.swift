import AppKit
import PuggleSlidesKit
import SwiftUI

/// Insert ▸ Word art: type the text, then Return.
struct WordArtPrompt: View {
    var initial = ""
    var buttonTitle = "Insert"
    var title = "Word art"
    let insert: (String) -> Void
    let dismiss: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 20))
            PanelField(placeholder: "Type your text", text: $text)
                .frame(width: 320)
                .onSubmit(commit)
            HStack {
                Spacer()
                PanelButton(title: "Cancel", primary: false, action: dismiss)
                PanelButton(title: buttonTitle, isEnabled: !text.trimmingCharacters(in: .whitespaces).isEmpty, action: commit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear { text = initial }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismiss()
        insert(trimmed)
    }
}

/// File ▸ Import slides: the other presentation's slides to pick from, and whether they keep their theme.
struct ImportSlidesView: View {
    let source: Presentation
    let name: String
    let importSlides: ([Int], Bool) -> Void
    let dismiss: () -> Void
    @State private var chosen = Set<Int>()
    @State private var keepsTheme = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import slides").font(.system(size: 20))
            HStack(spacing: 6) {
                Text("Select slides:").foregroundStyle(Theme.secondaryText)
                Button("All") { chosen = Set(source.slides.indices) }.buttonStyle(.link)
                Text("·").foregroundStyle(Theme.secondaryText)
                Button("None") { chosen = [] }.buttonStyle(.link)
                Spacer()
                Text(name).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            .font(.system(size: 13))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(180), spacing: 14), count: 3), spacing: 14) {
                    ForEach(source.slides.indices, id: \.self) { index in
                        Button {
                            if chosen.contains(index) { chosen.remove(index) } else { chosen.insert(index) }
                        } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: thumbnail(index))
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(chosen.contains(index) ? Theme.accent : Theme.divider,
                                                                                        lineWidth: chosen.contains(index) ? 3 : 1))
                                Text("\(index + 1)").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
            .frame(width: 600, height: 380)
            HStack {
                Toggle("Keep original theme", isOn: $keepsTheme)
                Spacer()
                PanelButton(title: "Cancel", primary: false, action: dismiss)
                PanelButton(title: chosen.count == 1 ? "Import slide" : "Import slides", isEnabled: !chosen.isEmpty) {
                    dismiss()
                    importSlides(chosen.sorted(), keepsTheme)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func thumbnail(_ index: Int) -> NSImage {
        let size = source.slideSize
        return SlideRenderer.image(of: source.slides[index], in: source, size: CGSize(width: 180, height: (180 * size.height / max(size.width, 1)).rounded()),
                                   slideNumber: index + 1, scale: 2)
    }
}

/// View ▸ Guides ▸ Edit guides: each guide's position (in inches from the slide's left or top edge) and color.
struct EditGuidesView: View {
    @State var guides: [Guide]
    let slideSize: SlideSize
    let apply: ([Guide]) -> Void
    let dismiss: () -> Void

    static let colors: [(String, RGBColor?)] = [("Default", nil), ("Red", RGBColor(red: 0xEA, green: 0x43, blue: 0x35)),
                                                ("Orange", RGBColor(red: 0xFF, green: 0x6D, blue: 0x01)), ("Green", RGBColor(red: 0x34, green: 0xA8, blue: 0x53)),
                                                ("Blue", RGBColor(red: 0x1A, green: 0x73, blue: 0xE8)), ("Purple", RGBColor(red: 0x93, green: 0x34, blue: 0xE6))]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit guides").font(.system(size: 20))
            if guides.isEmpty {
                Text("No guides").foregroundStyle(Theme.secondaryText)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($guides) { $guide in
                        HStack(spacing: 10) {
                            Image(systemName: guide.orientation == .vertical ? "arrow.left.and.right" : "arrow.up.and.down")
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 18)
                                .help(guide.orientation == .vertical ? "Vertical guide" : "Horizontal guide")
                            TextField("", value: Binding(get: { guide.position / 72 }, set: { guide.position = max(0, $0) * 72 }),
                                      format: .number.precision(.fractionLength(0...2)))
                                .frame(width: 70)
                            Text("in").foregroundStyle(Theme.secondaryText)
                            Picker("", selection: Binding(get: { Self.colors.firstIndex { $0.1 == guide.color } ?? 0 },
                                                          set: { guide.color = Self.colors[$0].1 })) {
                                ForEach(Self.colors.indices, id: \.self) { Text(Self.colors[$0].0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                            Spacer()
                            Button {
                                guides.removeAll { $0.id == guide.id }
                            } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                                .help("Delete guide")
                        }
                    }
                }
            }
            .frame(width: 360, height: min(260, CGFloat(max(1, guides.count)) * 34 + 8))
            HStack {
                Spacer()
                PanelButton(title: "Cancel", primary: false, action: dismiss)
                PanelButton(title: "Apply") {
                    apply(guides)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}
