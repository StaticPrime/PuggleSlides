import Foundation

public enum PresentationFormat: String, CaseIterable, Sendable {
    case pptx, odp

    public var typeIdentifier: String {
        switch self {
        case .pptx: "org.openxmlformats.presentationml.presentation"
        case .odp: "org.oasis-open.opendocument.presentation"
        }
    }

    public var fileExtension: String { rawValue }

    /// The name in File ▸ Download.
    public var displayName: String {
        switch self {
        case .pptx: "Microsoft PowerPoint (.pptx)"
        case .odp: "ODP Document (.odp)"
        }
    }

    /// The badge beside the title in the header.
    public var badge: String { "." + rawValue.uppercased() }

    /// Accepts a type identifier or a file extension.
    public init?(typeName: String) {
        let lowered = typeName.lowercased()
        if let format = PresentationFormat.allCases.first(where: { $0.typeIdentifier.lowercased() == lowered || $0.rawValue == lowered }) {
            self = format
        } else {
            return nil
        }
    }
}

/// Things in a file that PuggleSlides can't keep yet. A file with any of them opens as an untitled copy.
public enum ImportWarning: String, Hashable, Sendable, CaseIterable {
    case tables, charts, diagrams, video, audio, animations, transitions, comments, embeddedObjects, ink, otherContent

    /// Plural wording for "PuggleSlides can't keep some charts, SmartArt diagrams and videos yet". Tables, charts,
    /// animations and transitions are kept; only some of their kinds and settings aren't.
    public var userDescription: String {
        switch self {
        case .tables: "some tables"
        case .charts: "some charts"
        case .diagrams: "SmartArt diagrams"
        case .video: "videos"
        case .audio: "audio"
        case .animations: "some animations"
        case .transitions: "some transitions"
        case .comments: "comments"
        case .embeddedObjects: "embedded objects"
        case .ink: "ink drawings"
        case .otherContent: "some other content"
        }
    }
}

/// What reading a file produces.
public struct PresentationFile: Sendable {
    public var presentation: Presentation
    public var warnings: Set<ImportWarning>

    public init(presentation: Presentation, warnings: Set<ImportWarning> = []) {
        self.presentation = presentation
        self.warnings = warnings
    }
}

public enum PresentationIOError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case unwritable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let message), .unwritable(let message): message
        }
    }
}

public enum PresentationIO {
    public static func read(_ data: Data, format: PresentationFormat) throws -> PresentationFile {
        switch format {
        case .pptx: try PPTXReader.read(data)
        case .odp: try ODPReader.read(data)
        }
    }

    public static func write(_ presentation: Presentation, format: PresentationFormat) throws -> Data {
        switch format {
        case .pptx: try PPTXWriter.write(presentation)
        case .odp: try ODPWriter.write(presentation)
        }
    }
}
