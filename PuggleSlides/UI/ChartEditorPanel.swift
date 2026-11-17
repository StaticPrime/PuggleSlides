import AppKit
import PuggleSlidesKit
import SwiftUI

/// The chart editor: the chart's type, its numbers and labels, and how it looks. The numbers live with the chart,
/// so they're edited in this panel rather than in a separate spreadsheet.
struct ChartEditorPanel: View {
    let state: EditorState
    let actions: SidebarActions
    @State private var heading = ""
    @State private var labels: [String] = []
    @State private var names: [String] = []
    @State private var values: [[String]] = []
    @State private var title = ""
    @State private var horizontalTitle = ""
    @State private var verticalTitle = ""
    @State private var minimum = ""
    @State private var maximum = ""
    @State private var loadedID: UUID?
    @State private var loadedRevision = -1

    private var controller: PresentationController { actions.controller }
    private var element: SlideElement? { controller.selectedChart }

    var body: some View {
        let _ = state.revision
        VStack(alignment: .leading, spacing: 4) {
            if let element, let chart = element.chart {
                PanelSection(title: "Chart type") {
                    Picker("", selection: Binding(get: { chart.kind }, set: { kind in controller.editChart("Chart Type") { $0.kind = kind } })) {
                        ForEach(ChartKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
                PanelSection(title: "Data") { dataGrid(chart) }
                PanelSection(title: "Titles") {
                    field("Chart title", $title) { value in controller.editChart("Chart Title") { $0.title = value } }
                    if !chart.kind.isPie {
                        field("Horizontal axis title", $horizontalTitle) { value in controller.editChart("Axis Title") { $0.horizontalAxisTitle = value } }
                        field("Vertical axis title", $verticalTitle) { value in controller.editChart("Axis Title") { $0.verticalAxisTitle = value } }
                    }
                }
                PanelSection(title: "Legend") {
                    Picker("", selection: Binding(get: { chart.legend }, set: { legend in controller.editChart("Legend") { $0.legend = legend } })) {
                        ForEach(ChartLegendPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                PanelSection(title: "Chart style") {
                    if !chart.kind.isPie {
                        Toggle("Gridlines", isOn: Binding(get: { chart.showsGridlines },
                                                          set: { on in controller.editChart("Gridlines") { $0.showsGridlines = on } }))
                    }
                    // Pies always label their slices with percentages.
                    if !chart.kind.isPie {
                        Toggle("Data labels", isOn: Binding(get: { chart.showsDataLabels },
                                                            set: { on in controller.editChart("Data Labels") { $0.showsDataLabels = on } }))
                    }
                    if chart.kind == .donut {
                        AdjustmentSlider(title: "Doughnut hole", value: chart.pieHole, range: 0.1...0.9) { value in
                            controller.editChart("Doughnut Hole") { $0.pieHole = value }
                        }
                    }
                    if !chart.kind.isPie {
                        HStack(spacing: 8) {
                            field("Axis minimum", $minimum, width: 90) { value in
                                controller.editChart("Axis Range") { $0.verticalMinimum = Double(value.trimmingCharacters(in: .whitespaces)) }
                            }
                            field("Axis maximum", $maximum, width: 90) { value in
                                controller.editChart("Axis Range") { $0.verticalMaximum = Double(value.trimmingCharacters(in: .whitespaces)) }
                            }
                        }
                    }
                }
                .font(.system(size: 13))
                if !chart.kind.isPie {
                    PanelSection(title: "Series colors") {
                        ForEach(chart.data.series.indices, id: \.self) { index in
                            HStack {
                                Circle().fill(color(chart.color(ofSeries: index))).frame(width: 14, height: 14)
                                Text(chart.data.series[index].name.isEmpty ? "Series \(index + 1)" : chart.data.series[index].name)
                                    .font(.system(size: 13))
                                Spacer()
                                Menu("Color") {
                                    Button("Automatic") { controller.editChart("Series Color") { $0.data.series[index].color = nil } }
                                    ForEach(Chart.palette.indices, id: \.self) { paletteIndex in
                                        Button {
                                            controller.editChart("Series Color") { $0.data.series[index].color = Chart.palette[paletteIndex] }
                                        } label: {
                                            Image(nsImage: Self.swatch(Chart.palette[paletteIndex]))
                                            Text(Self.paletteNames[paletteIndex])
                                        }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 70)
                            }
                        }
                    }
                }
            } else {
                Text("Select a chart to edit its data and look.").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: state.revision) { _, _ in reload() }
    }

    private func color(_ rgb: RGBColor) -> Color {
        Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    private func field(_ placeholder: String, _ text: Binding<String>, width: CGFloat = 240, commit: @escaping (String) -> Void) -> some View {
        PanelField(placeholder: placeholder, text: text)
            .frame(width: width)
            .onSubmit { commit(text.wrappedValue) }
    }

    // MARK: The data grid

    /// Labels down the left, one column per series, as in a spreadsheet.
    private func dataGrid(_ chart: Chart) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        cell($heading, header: true)
                        ForEach(names.indices, id: \.self) { column in
                            cell(Binding(get: { names.indices.contains(column) ? names[column] : "" }, set: { if names.indices.contains(column) { names[column] = $0 } }),
                                 header: true)
                        }
                    }
                    ForEach(labels.indices, id: \.self) { row in
                        HStack(spacing: 3) {
                            cell(Binding(get: { labels.indices.contains(row) ? labels[row] : "" }, set: { if labels.indices.contains(row) { labels[row] = $0 } }))
                            ForEach(names.indices, id: \.self) { column in
                                cell(Binding(get: { value(row, column) }, set: { setValue(row, column, $0) }), number: true)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(width: 270)
            HStack(spacing: 6) {
                PanelButton(title: "Add row", primary: false) { change { $0.labels.append("Item \($0.labels.count + 1)") } }
                PanelButton(title: "Add series", primary: false) {
                    change { data in data.series.append(ChartSeries(name: "Series \(data.series.count + 1)", values: Array(repeating: nil, count: data.rowCount))) }
                }
            }
            HStack(spacing: 6) {
                PanelButton(title: "Remove row", primary: false, isEnabled: labels.count > 1) {
                    change { data in
                        data = data.padded()
                        data.labels.removeLast()
                        for index in data.series.indices { data.series[index].values.removeLast() }
                    }
                }
                PanelButton(title: "Remove series", primary: false, isEnabled: names.count > 1) { change { $0.series.removeLast() } }
            }
            Text("Press Return to apply a change.").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        }
    }

    private func cell(_ text: Binding<String>, header: Bool = false, number: Bool = false) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: header ? .medium : .regular))
            .multilineTextAlignment(number ? .trailing : .leading)
            .padding(.horizontal, 4)
            .frame(width: 70, height: 22)
            .background(RoundedRectangle(cornerRadius: 3).fill(header ? Theme.toolbarFill : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.divider))
            .onSubmit(commitGrid)
    }

    private func value(_ row: Int, _ column: Int) -> String {
        guard values.indices.contains(column), values[column].indices.contains(row) else { return "" }
        return values[column][row]
    }

    private func setValue(_ row: Int, _ column: Int, _ text: String) {
        guard values.indices.contains(column), values[column].indices.contains(row) else { return }
        values[column][row] = text
    }

    /// Applies the grid as typed: numbers where they parse, gaps where they don't.
    private func commitGrid() {
        let names = self.names, labels = self.labels, values = self.values, heading = self.heading
        controller.editChart("Edit Chart Data") { chart in
            chart.data.labelHeading = heading
            chart.data.labels = labels
            chart.data.series = names.indices.map { index in
                let numbers = (values.indices.contains(index) ? values[index] : []).map { Double($0.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }
                return ChartSeries(name: names[index], values: numbers, color: chart.data.series.indices.contains(index) ? chart.data.series[index].color : nil)
            }
        }
    }

    private func change(_ edit: @escaping (inout ChartData) -> Void) {
        commitGrid()
        controller.editChart("Edit Chart Data") { chart in
            var data = chart.data.padded()
            edit(&data)
            chart.data = data
        }
    }

    private func reload() {
        guard let element, let chart = element.chart else { return }
        guard loadedID != element.id || loadedRevision != state.revision else { return }
        loadedID = element.id
        loadedRevision = state.revision
        let data = chart.data.padded()
        heading = data.labelHeading
        labels = data.labels
        names = data.series.map(\.name)
        values = data.series.map { $0.values.map { $0.map(Self.format) ?? "" } }
        title = chart.title
        horizontalTitle = chart.horizontalAxisTitle
        verticalTitle = chart.verticalAxisTitle
        minimum = chart.verticalMinimum.map(Self.format) ?? ""
        maximum = chart.verticalMaximum.map(Self.format) ?? ""
    }

    /// Names for the chart palette's series colors.
    static let paletteNames = ["Blue", "Red", "Yellow", "Green", "Orange", "Cyan", "Light blue", "Light red", "Light yellow", "Light green",
                               "Light orange", "Light cyan"]

    static func swatch(_ color: RGBColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

/// Format options ▸ Recolor and Adjustments, for pictures.
struct ImageOptionsSections: View {
    let element: SlideElement
    let controller: PresentationController

    var body: some View {
        let adjustments = element.picture?.adjustments ?? .none
        let theme = controller.currentSlide.map { controller.presentation.theme(for: $0) } ?? controller.presentation.themes.first
        PanelSection(title: "Recolor") {
            Menu(adjustments.recolor?.title ?? "No recolor") {
                Button("No recolor") { controller.setImageAdjustments("Recolor") { $0.recolor = nil } }
                Divider()
                ForEach(Array(ImageRecolor.presets.enumerated()), id: \.offset) { _, recolor in
                    Button {
                        controller.setImageAdjustments("Recolor") { $0.recolor = recolor }
                    } label: {
                        if let theme { Image(nsImage: swatch(recolor, theme: theme)) }
                        Text(recolor.title)
                    }
                }
            }
            .frame(width: 220)
        }
        PanelSection(title: "Adjustments") {
            slider("Opacity", value: 1 - adjustments.transparency, range: 0...1) { value in
                controller.setImageAdjustments("Opacity") { $0.transparency = 1 - value }
            }
            slider("Brightness", value: adjustments.brightness, range: -1...1) { value in
                controller.setImageAdjustments("Brightness") { $0.brightness = value }
            }
            slider("Contrast", value: adjustments.contrast, range: -1...1) { value in
                controller.setImageAdjustments("Contrast") { $0.contrast = value }
            }
            PanelButton(title: "Reset", primary: false, isEnabled: !adjustments.isNone) {
                controller.setImageAdjustments("Reset Adjustments") { $0 = .none }
            }
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, commit: @escaping (Double) -> Void) -> some View {
        AdjustmentSlider(title: title, value: value, range: range, commit: commit)
    }

    /// The recolor's two ends, side by side, for the menu.
    private func swatch(_ recolor: ImageRecolor, theme: SlideTheme) -> NSImage {
        let ends = recolor.ends(in: theme.colors)
        return NSImage(size: NSSize(width: 28, height: 14), flipped: false) { rect in
            NSGradient(starting: NSColor(srgbRed: ends.dark.red, green: ends.dark.green, blue: ends.dark.blue, alpha: 1),
                       ending: NSColor(srgbRed: ends.light.red, green: ends.light.green, blue: ends.light.blue, alpha: 1))?.draw(in: rect, angle: 0)
            return true
        }
    }
}

/// A labeled slider that applies its value when the drag ends (one undo step per change).
struct AdjustmentSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let commit: (Double) -> Void
    @State private var current = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("\(Int((current * 100).rounded()))%").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
            Slider(value: $current, in: range) { editing in
                if !editing { commit(current) }
            }
        }
        .frame(width: 240)
        .onAppear { current = value }
        .onChange(of: value) { _, newValue in current = newValue }
    }
}
