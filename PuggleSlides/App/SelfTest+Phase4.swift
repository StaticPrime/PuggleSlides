#if DEBUG
import AppKit
import PuggleSlidesKit

/// Phase 4: comments, find and replace, and accessibility.
extension SelfTest {
    /// The menu bar's item with a shortcut.
    static func menuItem(key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        let mask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        func search(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.keyEquivalent == key, item.keyEquivalentModifierMask.intersection(mask) == modifiers.intersection(mask) { return item }
                if let submenu = item.submenu, let found = search(submenu) { return found }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(search)
    }

    /// Whatever would carry out a command in a document window if it were in front: its responder chain, then its
    /// window, controller, document, the app and the document controller. The test runs whether or not the app is in front.
    static func handler(for action: Selector, in window: DocumentWindowController) -> AnyObject? {
        var responder: NSResponder? = window.window?.firstResponder
        while let current = responder {
            if current.responds(to: action) { return current }
            responder = current.nextResponder
        }
        let others: [AnyObject?] = [window.window, window.window?.delegate, window, window.document as AnyObject?, NSApp, NSApp.delegate,
                                    NSDocumentController.shared]
        return others.compactMap { $0 }.first { $0.responds(to: action) }
    }

    /// Uses a menu shortcut: finds its item in the menu bar and sends its command to the document window, as
    /// pressing the keys would with the window in front.
    static func shortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags, in window: DocumentWindowController) {
        guard let item = menuItem(key: key, modifiers: modifiers), let action = item.action else {
            check(false, "the menu bar has a command for \(modifiers) \(key)")
            return
        }
        guard let target = handler(for: action, in: window) else { return }
        if let validator = target as? NSMenuItemValidation, !validator.validateMenuItem(item) { return }
        _ = target.perform(action, with: item)
    }

    static func addPhase4Steps(_ window: DocumentWindowController) {
        let controller = window.controller
        let state = window.state
        var slide: Slide { controller.currentSlide! }
        var boxID = UUID()
        var commentSlideID = UUID()
        var threadID = UUID()
        var thread: CommentThread? {
            controller.presentation.commentLocation(of: threadID).map { controller.presentation.slides[$0.slide].comments[$0.thread] }
        }
        var boxText: String { controller.presentation.slides.first { $0.id == commentSlideID }?.element(id: boxID)?.shape?.text?.plainText ?? "" }
        let question = "Is this the final number?"

        // Comments.
        step {
            let theme = controller.presentation.theme(for: slide)
            controller.newSlide(layoutID: theme.layout(kind: .blank)?.id)
            commentSlideID = slide.id
            let box = SlideElement(name: "TextBox 1", placement: Placement(frame: SlideRect(x: 60, y: 60, width: 360, height: 60)),
                                   content: .shape(Shape(text: TextBody("Walks are up this spring"))))
            boxID = box.id
            controller.insert([box], actionName: "Insert Text Box")
            shortcut("m", [.command, .option], in: window)
            check(state.commentDraft == CommentDraft(slideID: commentSlideID, elementID: boxID),
                  "Insert ▸ Comment (⌥⌘M) starts a comment about the selected object")
            check(window.commentsWidth.constant > 0, "the comment is written beside the slide")
            window.postComment(question)
            threadID = slide.comments.last?.id ?? UUID()
            check(thread?.elementID == boxID && thread?.first?.text == question && thread?.first?.author == controller.commentAuthor,
                  "posting starts a thread about the object, signed with the account's name")
            check(state.commentDraft == nil && state.selectedCommentID == threadID, "the new thread's card is selected")
        }
        step {
            controller.replyToComment(threadID, text: "Yes, it’s final.")
            check(thread?.comments.count == 2, "Reply adds to the thread")
        }
        step {
            if let reply = thread?.comments.last { controller.editComment(reply.id, inThread: threadID, text: "Yes, it is final.") }
            check(thread?.comments.last?.text == "Yes, it is final." && thread?.comments.last?.editedDate != nil,
                  "Edit changes a comment and marks it edited")
        }
        step {
            controller.undoManager?.undo()
            check(thread?.comments.last?.text == "Yes, it’s final." && thread?.comments.last?.editedDate == nil, "undo puts a comment back as it was")
        }
        step {
            controller.setThread(threadID, resolved: true)
            check(thread?.isResolved == true && controller.openThreads(onSlide: commentSlideID).isEmpty, "Resolve takes a thread from beside the slide")
            check(controller.presentation.commentThreads.contains { $0.thread.id == threadID }, "a resolved thread stays in the comment history")
        }
        step {
            check(window.commentsWidth.constant == 0, "the comments column closes when no comment is open")
            shortcut("a", [.command, .option, .shift], in: window)
            check(state.sidebar == .comments, "Open comment history (⌥⇧⌘A) shows the comments panel")
            controller.setThread(threadID, resolved: false)
        }
        step {
            controller.selectSlide(controller.presentation.slides[0].id)
            window.openComment(threadID)
            check(controller.currentSlideID == commentSlideID && controller.selectedElementIDs == [boxID] && state.selectedCommentID == threadID,
                  "a thread in the comments panel opens on its slide with its object selected")
            window.closeSidebar()
            shortcut("j", [.command, .option, .shift], in: window)
            check(!state.showsComments && window.commentsWidth.constant == 0, "View ▸ Comments ▸ Show comments (⌥⇧⌘J) hides the column")
            shortcut("j", [.command, .option, .shift], in: window)
            check(state.showsComments && window.commentsWidth.constant > 0, "and shows it again")
        }
        step {
            controller.duplicateSlides()
            check(slide.id != commentSlideID && slide.comments.isEmpty && thread != nil, "a duplicated slide leaves its comments behind")
        }
        step { controller.undoManager?.undo() }
        step {
            if let first = thread?.first { controller.deleteComment(first.id, inThread: threadID) }
            check(thread == nil, "deleting a thread's first comment deletes the thread")
        }
        step { controller.undoManager?.undo() }
        step {
            check(thread?.comments.count == 2, "undo brings a deleted thread back")
            for format in [PresentationFormat.pptx, .odp] {
                let name = format == .pptx ? "a PowerPoint" : "an OpenDocument"
                do {
                    let file = try PresentationIO.read(try PresentationIO.write(controller.presentation, format: format), format: format)
                    let texts = file.presentation.commentThreads.flatMap { $0.thread.comments.map(\.text) }
                    check(texts.contains(question) && texts.contains("Yes, it’s final."), "\(name) file keeps comments", "\(texts)")
                    check(!file.warnings.contains(.comments), "\(name) file with comments opens as itself")
                } catch {
                    check(false, "\(name) file with comments", "\(error)")
                }
            }
        }

        // Find and replace.
        step {
            controller.setNotes(TextBody("Plan more walks for the team"), slideID: commentSlideID)
            shortcut("f", [.command], in: window)
            check(window.findPanel != nil, "Find (⌘F) opens Find and replace")
            window.findState.query = "walks"
            window.findChanged()
            let here = window.findResults.filter { $0.slideID == commentSlideID }
            check(here.map(\.place) == [.element([boxID]), .notes], "Find looks in objects and speaker notes", "\(here.map(\.place))")
            check(window.canvas.findMatches.contains { $0.place == .element([boxID]) }, "matches on the slide are marked")
            check(window.findState.message?.contains(" of ") == true, "the dialog says which match is shown", window.findState.message ?? "")
        }
        step {
            // Show the match in the text box, then replace it.
            for _ in window.findResults {
                guard let current = window.currentFindMatch, current.place != .element([boxID]) || current.slideID != commentSlideID else { break }
                window.findNext(forward: true)
            }
            window.findState.replacement = "Strolls"
            window.replaceCurrent()
            check(boxText == "Strolls are up this spring", "Replace changes the match shown", boxText)
            check(window.currentFindMatch?.place == .notes, "Replace moves on to the next match")
        }
        step {
            controller.undoManager?.undo()
            check(boxText == "Walks are up this spring", "undo takes a replacement back", boxText)
        }
        step {
            window.findState.query = "walks"
            window.findState.replacement = "hikes"
            window.findChanged()
            let before = window.findResults.count
            window.replaceAllMatches()
            check(before >= 2 && window.findResults.isEmpty && window.findState.message == "Replaced \(before) instances",
                  "Replace all changes every match and says how many", window.findState.message ?? "")
            check(controller.presentation.slides.first { $0.id == commentSlideID }?.notes.plainText == "Plan more hikes for the team",
                  "Replace all reaches the speaker notes")
        }
        step {
            controller.undoManager?.undo()
            check(boxText == "Walks are up this spring", "one undo takes back Replace all", boxText)
            window.findState.usesRegularExpression = true
            window.findState.query = "(walks"
            window.findChanged()
            check(window.findState.messageIsProblem && window.findResults.isEmpty, "a regular expression that can't be used is reported")
            window.findState.query = "W[a-z]+s"
            window.findState.matchesCase = true
            window.findChanged()
            check(window.findResults.contains { $0.place == .element([boxID]) }, "Match using regular expressions finds patterns")
            window.findState.usesRegularExpression = false
            window.findState.matchesCase = false
            window.closeFindReplace()
            check(window.findPanel == nil && window.canvas.findMatches.isEmpty, "closing Find and replace clears the marks")
        }

        // Accessibility.
        step {
            controller.selectSlide(commentSlideID)
            controller.selectElements([])
            let objects = window.canvas.accessibilityChildren()?.compactMap { $0 as? SlideObjectAccessibility } ?? []
            check(objects.count == slide.elements.count, "VoiceOver finds every object on the slide")
            let box = objects.first { $0.elementID == boxID }
            check(box?.accessibilityValue() as? String == "Walks are up this spring" && box?.accessibilityRole() == .staticText,
                  "a text box reads as its text")
            let frame = box?.accessibilityFrame() ?? .zero
            check(frame.width > 10 && (window.window?.frame.intersects(frame) ?? false), "objects are where they're drawn on screen", "\(frame)")
            check(window.canvas.accessibilityLabel()?.hasPrefix("Slide \((controller.currentSlideIndex ?? 0) + 1) of ") == true,
                  "the slide says which slide it is", window.canvas.accessibilityLabel() ?? "")
            _ = box?.accessibilityPerformPress()
            check(controller.selectedElementIDs == [boxID], "pressing an object with VoiceOver selects it")
            let thumbnails = window.filmstrip.accessibilityChildren()?.compactMap { $0 as? SlideThumbnailAccessibility } ?? []
            check(thumbnails.count == controller.presentation.slides.count, "VoiceOver finds every slide in the filmstrip")
            check((window.filmstrip.accessibilitySelectedChildren()?.first as? SlideThumbnailAccessibility)?.slideID == controller.currentSlideID,
                  "the current slide is the selected one")
            check(thumbnails.first { $0.slideID == commentSlideID }?.accessibilityLabel()?.contains("1 comment") == true,
                  "a slide's comments are mentioned")
        }
        step {
            _ = controller.insertImage(data: SampleContent.sampleImage())
            controller.setAltText(title: nil, description: "A puggle on a walk")
            let picture = window.canvas.accessibilityChildren()?.compactMap { $0 as? SlideObjectAccessibility }
                .first { $0.elementID == controller.selectedElementIDs.first }
            check(picture?.accessibilityLabel() == "A puggle on a walk" && picture?.accessibilityRole() == .image, "alt text names a picture")
        }
        step {
            shortcut("f", [.command, .option, .shift], in: window)
            check(window.window?.firstResponder === window.filmstrip, "⌥⇧⌘F moves to the filmstrip")
            shortcut("c", [.command, .option, .shift], in: window)
            check(window.window?.firstResponder === window.canvas, "⌥⇧⌘C moves to the slide")
            shortcut("s", [.command, .option, .shift], in: window)
            check(window.window?.firstResponder === window.notes.textView, "⌥⇧⌘S moves to the speaker notes")
            window.focusCanvas()
        }

        // Every command in the menu bar reaches something that carries it out.
        step {
            var unhandled: [String] = []
            @MainActor func visit(_ menu: NSMenu, path: String) {
                for item in menu.items {
                    let name = path.isEmpty ? item.title : "\(path) ▸ \(item.title)"
                    if let submenu = item.submenu { visit(submenu, path: name) }
                    guard let action = item.action, item.target == nil else { continue }
                    if handler(for: action, in: window) == nil { unhandled.append(name) }
                }
            }
            if let menu = NSApp.mainMenu { visit(menu, path: "") }
            check(unhandled.isEmpty, "every menu command has something to carry it out", unhandled.joined(separator: ", "))
        }
    }
}
#endif
