import AppKit
import PuggleSlidesKit

/// A presentation window's model: the presentation and file handling.
@objc(PresentationDocument)
final class PresentationDocument: NSDocument {
    var presentation = Presentation.makeDefault()
    /// Features found while importing that could not be kept.
    private(set) var importWarnings: Set<ImportWarning> = []
    /// Title typed into the header before the presentation has a file.
    var customTitle: String?
    /// The original file name when a lossy import was reopened as an untitled copy.
    private(set) var importedFileName: String?

    var onStatusChange: (() -> Void)?
    /// Called after the contents were replaced from a file (Revert).
    var onReload: (() -> Void)?
    /// Asked to commit any text being edited before the presentation is saved.
    var onWillSave: (() -> Void)?

    /// Content parsed off the main thread, applied once the main actor can take it.
    nonisolated(unsafe) private var pendingFile: PresentationFile?

    override init() {
        super.init()
        hasUndoManager = true
    }

    nonisolated override class var autosavesInPlace: Bool { true }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        if let file = pendingFile {
            pendingFile = nil
            apply(file)
        }
        #if DEBUG
        if fileURL == nil, DebugLaunchOptions.wantsSample, presentation.slides.count == 1, presentation.slides[0].elements.allSatisfy({ $0.shape?.text?.isEmpty ?? true }) {
            presentation = SampleContent.make()
        }
        #endif
        if !importWarnings.isEmpty, let url = fileURL {
            // Never overwrite a file with a lossy copy: continue as an untitled presentation.
            importedFileName = url.deletingPathExtension().lastPathComponent
            fileURL = nil
            fileType = PresentationFormat.pptx.typeIdentifier
        }
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: Reading and writing

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let format = PresentationFormat(typeName: typeName) else {
            throw PresentationIOError.unreadable("PuggleSlides can't open files of this type.")
        }
        let file = try PresentationIO.read(data, format: format)
        if Thread.isMainThread {
            MainActor.assumeIsolated { apply(file) }
        } else {
            pendingFile = file
        }
    }

    private func apply(_ file: PresentationFile) {
        presentation = file.presentation
        importWarnings = file.warnings
        undoManager?.removeAllActions()
        onReload?()
    }

    /// True while macOS autosaves: text being typed stays in its editor until the person finishes.
    private var isAutosaving = false

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        isAutosaving = saveOperation == .autosaveInPlaceOperation || saveOperation == .autosaveElsewhereOperation
            || saveOperation == .autosaveAsOperation
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            self?.isAutosaving = false
            completionHandler(error)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let format = PresentationFormat(typeName: typeName) else {
            throw PresentationIOError.unwritable("PuggleSlides can't save files of this type.")
        }
        if !isAutosaving { onWillSave?() }
        var copy = presentation
        copy.removeUnusedMedia()
        if copy.title == nil || copy.title?.isEmpty == true { copy.title = displayName }
        return try PresentationIO.write(copy, format: format)
    }

    var format: PresentationFormat? { fileType.flatMap(PresentationFormat.init(typeName:)) }

    // MARK: Names

    override var displayName: String! {
        get {
            if fileURL == nil, let title = customTitle ?? importedFileName { return title }
            let name: String = super.displayName
            if fileURL == nil, name.hasPrefix("Untitled") { return name.replacingOccurrences(of: "Untitled", with: "Untitled presentation") }
            return name
        }
        set { super.displayName = newValue }
    }

    // MARK: Status

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        onStatusChange?()
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        onStatusChange?()
    }
}
