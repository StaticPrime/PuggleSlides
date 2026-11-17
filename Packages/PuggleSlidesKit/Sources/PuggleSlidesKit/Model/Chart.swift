import Foundation

/// The chart types the chart editor offers.
public enum ChartKind: String, Codable, CaseIterable, Sendable {
    case column, stackedColumn, percentColumn
    case bar, stackedBar, percentBar
    case line, smoothLine
    case area, stackedArea, percentArea
    case pie, donut
    case scatter

    public var title: String {
        switch self {
        case .column: "Column chart"
        case .stackedColumn: "Stacked column chart"
        case .percentColumn: "100% stacked column chart"
        case .bar: "Bar chart"
        case .stackedBar: "Stacked bar chart"
        case .percentBar: "100% stacked bar chart"
        case .line: "Line chart"
        case .smoothLine: "Smooth line chart"
        case .area: "Area chart"
        case .stackedArea: "Stacked area chart"
        case .percentArea: "100% stacked area chart"
        case .pie: "Pie chart"
        case .donut: "Doughnut chart"
        case .scatter: "Scatter chart"
        }
    }

    public var isPie: Bool { self == .pie || self == .donut }
    public var isBar: Bool { self == .bar || self == .stackedBar || self == .percentBar }
    public var isStacked: Bool { [.stackedColumn, .stackedBar, .stackedArea].contains(self) }
    public var isPercent: Bool { [.percentColumn, .percentBar, .percentArea].contains(self) }
}

public enum ChartLegendPosition: String, Codable, CaseIterable, Sendable {
    case auto, top, bottom, left, right, none

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .top: "Top"
        case .bottom: "Bottom"
        case .left: "Left"
        case .right: "Right"
        case .none: "None"
        }
    }
}

/// One series of numbers, one value per label; nil is a gap.
public struct ChartSeries: Hashable, Codable, Sendable {
    public var name: String
    public var values: [Double?]
    /// Nil uses the next of the palette's series colors.
    public var color: RGBColor?

    public init(name: String, values: [Double?], color: RGBColor? = nil) {
        self.name = name
        self.values = values
        self.color = color
    }
}

/// The numbers a chart shows, kept in the presentation as PowerPoint keeps a chart's workbook: the label column
/// and one column per series.
public struct ChartData: Hashable, Codable, Sendable {
    /// The label column's heading ("Month").
    public var labelHeading: String
    public var labels: [String]
    public var series: [ChartSeries]

    public init(labelHeading: String = "", labels: [String] = [], series: [ChartSeries] = []) {
        self.labelHeading = labelHeading
        self.labels = labels
        self.series = series
    }

    /// Rows: the labels, or the longest series.
    public var rowCount: Int { max(labels.count, series.map(\.values.count).max() ?? 0) }

    /// Every series padded with gaps (and the labels with blanks) to the same length.
    public func padded() -> ChartData {
        let count = rowCount
        var copy = self
        copy.labels += Array(repeating: "", count: max(0, count - labels.count))
        for index in copy.series.indices {
            copy.series[index].values += Array(repeating: nil, count: max(0, count - copy.series[index].values.count))
        }
        return copy
    }
}

/// A chart drawn from numbers stored with it (Insert ▸ Chart).
public struct Chart: Hashable, Codable, Sendable {
    public var kind: ChartKind
    public var data: ChartData
    public var title: String
    public var horizontalAxisTitle: String
    public var verticalAxisTitle: String
    public var legend: ChartLegendPosition
    public var showsGridlines: Bool
    public var showsDataLabels: Bool
    /// The hole in a doughnut chart, as a fraction of the radius.
    public var pieHole: Double
    /// Nil uses the chart default (Roboto, falling back to Arial).
    public var fontFamily: String?
    /// Nil is white.
    public var backgroundColor: RGBColor?
    public var verticalMinimum: Double?
    public var verticalMaximum: Double?

    public init(kind: ChartKind, data: ChartData, title: String = "", horizontalAxisTitle: String = "", verticalAxisTitle: String = "",
                legend: ChartLegendPosition = .auto, showsGridlines: Bool = true, showsDataLabels: Bool = false, pieHole: Double = 0.5,
                fontFamily: String? = nil, backgroundColor: RGBColor? = nil, verticalMinimum: Double? = nil, verticalMaximum: Double? = nil) {
        self.kind = kind
        self.data = data
        self.title = title
        self.horizontalAxisTitle = horizontalAxisTitle
        self.verticalAxisTitle = verticalAxisTitle
        self.legend = legend
        self.showsGridlines = showsGridlines
        self.showsDataLabels = showsDataLabels
        self.pieHole = pieHole
        self.fontFamily = fontFamily
        self.backgroundColor = backgroundColor
        self.verticalMinimum = verticalMinimum
        self.verticalMaximum = verticalMaximum
    }

    /// The series colors charts use by default.
    public static let palette: [RGBColor] = [
        RGBColor(red: 0x42, green: 0x85, blue: 0xF4), RGBColor(red: 0xEA, green: 0x43, blue: 0x35), RGBColor(red: 0xFB, green: 0xBC, blue: 0x04),
        RGBColor(red: 0x34, green: 0xA8, blue: 0x53), RGBColor(red: 0xFF, green: 0x6D, blue: 0x01), RGBColor(red: 0x46, green: 0xBD, blue: 0xC6),
        RGBColor(red: 0x7B, green: 0xAA, blue: 0xF7), RGBColor(red: 0xF0, green: 0x7B, blue: 0x72), RGBColor(red: 0xFC, green: 0xD0, blue: 0x4F),
        RGBColor(red: 0x71, green: 0xC2, blue: 0x87), RGBColor(red: 0xFF, green: 0x99, blue: 0x4D), RGBColor(red: 0x7E, green: 0xD1, blue: 0xD7),
    ]

    /// A series' color: its own, or the palette's in turn.
    public func color(ofSeries index: Int) -> RGBColor {
        if data.series.indices.contains(index), let color = data.series[index].color { return color }
        return Self.palette[index % Self.palette.count]
    }

    /// A pie slice's color: pies color each label, not each series.
    public func color(ofSlice index: Int) -> RGBColor { Self.palette[index % Self.palette.count] }

    /// The chart Insert ▸ Chart adds: sample numbers to replace.
    public static func sample(_ kind: ChartKind) -> Chart {
        let labels = ["Item 1", "Item 2", "Item 3", "Item 4"]
        let series: [ChartSeries] = kind.isPie
            ? [ChartSeries(name: "Series 1", values: [40, 25, 20, 15])]
            : [ChartSeries(name: "Series 1", values: [10, 22, 18, 30]), ChartSeries(name: "Series 2", values: [14, 12, 25, 21])]
        return Chart(kind: kind, data: ChartData(labelHeading: "Category", labels: labels, series: series), title: kind.isPie ? "Series 1" : "")
    }
}
