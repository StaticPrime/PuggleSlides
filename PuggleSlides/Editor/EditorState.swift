import AppKit
import Observation
import PuggleSlidesKit

enum SaveStatus: Equatable {
    case draft, edited, saved

    var text: String {
        switch self {
        case .draft: "Not saved to a file yet"
        case .edited: "Saving…"
        case .saved: "Saved to this Mac"
        }
    }

    var symbol: String {
        switch self {
        case .draft: "doc.badge.clock"
        case .edited: "arrow.triangle.2.circlepath"
        case .saved: "checkmark.circle"
        }
    }
}

/// The Line menu: lines, arrows and connectors.
enum LineKind: String, CaseIterable {
    case line, arrow, elbow, curved

    var title: String {
        switch self {
        case .line: "Line"
        case .arrow: "Arrow"
        case .elbow: "Elbow connector"
        case .curved: "Curved connector"
        }
    }

    var preset: String {
        switch self {
        case .line, .arrow: "straightConnector1"
        case .elbow: "bentConnector3"
        case .curved: "curvedConnector3"
        }
    }

    var symbol: String {
        switch self {
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .elbow: "arrow.turn.down.right"
        case .curved: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

/// What a click on the canvas does.
enum CanvasTool: Equatable {
    case select
    case textBox
    case shape(String)
    case line(LineKind)

    var isInsertTool: Bool { self != .select }
}

/// What's selected, which decides the toolbar's right-hand controls.
enum SelectionKind: Equatable {
    case none, textBox, shape, line, image, group, multiple, table, chart, wordArt, media
}

/// The selected text's formatting, as the toolbar shows it. Nil means mixed.
struct TextSummary: Equatable {
    var fontFamily: String?
    var fontSize: Double?
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var colorHex: String?
    var highlightHex: String?
    var alignment: PuggleSlidesKit.TextAlignment? = .left
    var lineSpacing: Double?
    var isBulleted = false
    var isNumbered = false
    var anchor: VerticalAnchor? = .top
    var hasLink = false
}

/// The selected shapes' fill and border, as the toolbar shows them. Nil means mixed or none.
struct ShapeSummary: Equatable {
    var fillHex: String?
    var borderHex: String?
    var borderWidth: Double?
    var dash: DashStyle?
    var head: LineEnd?
    var tail: LineEnd?
}

/// What can be done to a presentation here.
enum DocumentAccess: Equatable {
    /// Everything: the presentation is this person's, or shared with them to edit.
    case full
    /// Shared with them to see and comment on: comments, but no changes to the slides.
    case commentOnly
    /// Nothing for now: its shared copy is still on its way.
    case locked
    /// A shared presentation whose changes can't be saved to iCloud just now (the Mac is offline, say): it can be seen,
    /// presented, printed and copied, comments included, but nothing in it changes until iCloud takes changes again.
    /// Nothing is kept to send later.
    case offline
}

/// Insert ▸ Comment: the comment being written, about an object or the slide.
struct CommentDraft: Equatable {
    var slideID: UUID
    var elementID: UUID?
}

@Observable
final class EditorState {
    var title = "Untitled presentation"
    var formatBadge: String?
    var saveStatus: SaveStatus = .draft
    /// Where the header row sits next to the window buttons (see `TitlebarMetrics`).
    var titlebarLeading: CGFloat = 78
    var titlebarCenterY: CGFloat = 18
    var banner: String?
    /// Incremented to ask the header to focus the title field (File ▸ Rename).
    var renameRequest = 0

    /// The canvas zoom, where 1 is 100%.
    var zoom: CGFloat = 1
    var zoomIsFit = true
    var canUndo = false
    var canRedo = false
    var tool = CanvasTool.select
    var isPaintFormatActive = false

    var selectionKind = SelectionKind.none
    var isEditingText = false
    /// The selection holds text that the text controls can format.
    var hasText = false
    var text = TextSummary()
    var shape = ShapeSummary()
    /// The current slide's layout name, shown by the Layout button.
    var layoutName = ""
    var slideCount = 1
    var currentSlideIndex = 0
    var showsSpeakerNotes = true
    /// The panel open on the right, if any.
    var sidebar: SidebarKind?
    /// The theme builder's bar: what's being edited ("Theme: Simple Light"), or nil when the builder is closed.
    var themeBuilderTitle: String?
    /// Incremented after every edit so panels re-read the presentation.
    var revision = 0
    /// View ▸ Comments ▸ Show comments: the column of comment cards beside the slide.
    var showsComments = true
    var commentDraft: CommentDraft?
    /// The thread whose card is selected in the column.
    var selectedCommentID: UUID?

    /// What sharing allows here.
    var access: DocumentAccess = .full
    /// Who the presentation is shared with, and how its shared copy is keeping up.
    let collaboration = CollaborationState()

    /// Only a presentation's owner shares it: people it's shared with don't get the Collaborate button.
    var showsCollaborateButton: Bool { !collaboration.isShared || collaboration.isOwner }
    /// Comments can be added, answered and changed by everyone who can edit or comment, but not while a shared copy is
    /// still opening or can't save to iCloud.
    var canComment: Bool { access == .full || access == .commentOnly }

    var zoomLabel: String { zoomIsFit ? "Fit" : "\(Int((zoom * 100).rounded()))%" }
}
