import AppKit
import PuggleSlidesKit
import SwiftUI

/// What the comment cards and the comments panel ask their window to do.
protocol CommentActions: AnyObject {
    var controller: PresentationController { get }
    /// Posts the comment being written (Insert ▸ Comment).
    func postComment(_ text: String)
    func cancelComment()
    /// A card was clicked: its thread becomes the selected one, and its object is selected.
    func selectThread(_ id: UUID)
    /// Shows a thread from the comments panel: its slide, its object and its card.
    func openComment(_ threadID: UUID)
}

/// A round badge with someone's initials, in a color that stays the same for a name.
struct AvatarView: View {
    let name: String
    var size: CGFloat = 28

    static let colors: [Color] = [
        Color(red: 0.10, green: 0.45, blue: 0.91), Color(red: 0.85, green: 0.19, blue: 0.15), Color(red: 0.12, green: 0.56, blue: 0.24),
        Color(red: 0.91, green: 0.44, blue: 0.04), Color(red: 0.56, green: 0.27, blue: 0.68), Color(red: 0.00, green: 0.54, blue: 0.58),
    ]

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        let index = abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.colors.count
        Circle()
            .fill(Self.colors[index])
            .frame(width: size, height: size)
            .overlay(Text(initials).font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(Color.white))
            .accessibilityHidden(true)
    }
}

/// A comment's date: "2:45 PM Today", "Nov 14".
func commentDateText(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) + " Today" }
    if calendar.isDateInYesterday(date) { return date.formatted(date: .omitted, time: .shortened) + " Yesterday" }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

/// A comment thread beside the slide: its comments, then (once the card is selected) a reply box; Resolve, and Edit
/// and Delete under More. Without a thread it's the composer for a new comment.
struct CommentCardView: View {
    let thread: CommentThread?
    let author: String
    let isSelected: Bool
    let actions: CommentActions
    @State private var reply = ""
    @State private var editing: UUID?
    @State private var editText = ""
    @FocusState private var replyFocused: Bool

    private var controller: PresentationController { actions.controller }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thread {
                ForEach(Array(thread.comments.enumerated()), id: \.element.id) { index, comment in
                    commentRow(comment, in: thread, isFirst: index == 0)
                }
            } else {
                HStack(spacing: 8) {
                    AvatarView(name: author)
                    Text(author).font(.system(size: 13, weight: .medium))
                }
            }
            // While comments can only be read (a shared presentation that can't save to iCloud), there's no reply box.
            if thread == nil || (isSelected && !controller.commentsAreReadOnly) {
                VStack(alignment: .trailing, spacing: 8) {
                    TextField(thread == nil ? "Comment" : "Reply", text: $reply, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...6)
                        .focused($replyFocused)
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(replyFocused ? Theme.accent : Theme.divider, lineWidth: replyFocused ? 2 : 1))
                        .onSubmit(send)
                    if thread == nil || !reply.isEmpty || replyFocused {
                        HStack {
                            PanelButton(title: "Cancel", primary: false) {
                                reply = ""
                                if thread == nil { actions.cancelComment() } else { replyFocused = false }
                            }
                            PanelButton(title: thread == nil ? "Comment" : "Reply",
                                        isEnabled: !reply.trimmingCharacters(in: .whitespaces).isEmpty) { send() }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white)
            .shadow(color: .black.opacity(isSelected || thread == nil ? 0.3 : 0.15), radius: isSelected || thread == nil ? 5 : 2, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: isSelected ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture { if let thread, !isSelected { actions.selectThread(thread.id) } }
        .onAppear { if thread == nil { replyFocused = true } }
        .onExitCommand { if thread == nil { actions.cancelComment() } else { replyFocused = false } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(thread.map { "Comment by \($0.first?.author ?? ""): \($0.first?.text ?? "")" } ?? "New comment")
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply = ""
        if let thread { controller.replyToComment(thread.id, text: text) } else { actions.postComment(text) }
    }

    @ViewBuilder private func commentRow(_ comment: Comment, in thread: CommentThread, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                AvatarView(name: comment.author)
                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(commentDateText(comment.date) + (comment.editedDate == nil ? "" : " (edited)"))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 4)
                if isFirst, !controller.commentsAreReadOnly {
                    ToolbarIconButton(symbol: "checkmark", help: "Mark as resolved and hide discussion") {
                        controller.setThread(thread.id, resolved: true)
                    }
                }
                if !controller.commentsAreReadOnly {
                    Menu {
                        // In a shared presentation, people edit what they wrote, and delete it (or anything, if they edit).
                        Button("Edit") {
                            editing = comment.id
                            editText = comment.text
                        }
                        .disabled(!controller.mayEditComment(comment))
                        Button("Delete") { controller.deleteComment(comment.id, inThread: thread.id) }
                            .disabled(!controller.mayDeleteComment(comment))
                    } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(Theme.secondaryText)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More options")
                    .accessibilityLabel("More options")
                }
            }
            if editing == comment.id, !controller.commentsAreReadOnly {
                TextField("", text: $editText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                HStack {
                    Spacer()
                    PanelButton(title: "Cancel", primary: false) { editing = nil }
                    PanelButton(title: "Save") {
                        controller.editComment(comment.id, inThread: thread.id, text: editText)
                        editing = nil
                    }
                }
            } else {
                Text(comment.text).font(.system(size: 13)).foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

/// The column of comments to the right of the slide: the current slide's open threads, and the composer for a new
/// one. It shows whenever the presentation has open comments, so the slide doesn't jump between slides.
struct CommentsColumn: View {
    let state: EditorState
    let actions: CommentActions

    var body: some View {
        let _ = state.revision
        let controller = actions.controller
        let threads = controller.openThreads(onSlide: controller.currentSlideID)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if state.commentDraft != nil {
                        CommentCardView(thread: nil, author: controller.commentAuthor, isSelected: true, actions: actions).id("draft")
                    }
                    ForEach(threads) { thread in
                        CommentCardView(thread: thread, author: controller.commentAuthor, isSelected: state.selectedCommentID == thread.id,
                                        actions: actions)
                            .id(thread.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: state.selectedCommentID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: Theme.canvas))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comments")
    }
}

/// The comments panel: every comment thread in the presentation, open or resolved.
struct CommentsPanel: View {
    let state: EditorState
    let actions: CommentActions
    @State private var filter = 0
    @State private var query = ""

    var body: some View {
        let _ = state.revision
        let controller = actions.controller
        let presentation = controller.presentation
        let search = query.trimmingCharacters(in: .whitespaces)
        let items = presentation.commentThreads.filter { item in
            guard filter == 0 || (filter == 1 ? !item.thread.isResolved : item.thread.isResolved) else { return false }
            return search.isEmpty || item.thread.comments.contains {
                $0.text.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $filter) {
                Text("All").tag(0)
                Text("Open").tag(1)
                Text("Resolved").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            PanelField(placeholder: "Search all comments", text: $query)
            if items.isEmpty {
                Text(!search.isEmpty ? "No comments match your search."
                     : filter == 2 ? "No resolved comments." : "No comments yet. Select an object and choose Insert ▸ Comment (⌥⌘M).")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(items, id: \.thread.id) { item in
                let number = (presentation.slideIndex(id: item.slideID) ?? 0) + 1
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Slide \(number)").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                        Spacer()
                        if item.thread.isResolved {
                            Text("Resolved").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if let first = item.thread.first {
                        HStack(spacing: 8) {
                            AvatarView(name: first.author, size: 22)
                            Text(first.author).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(commentDateText(first.date)).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                        }
                        Text(first.text).font(.system(size: 13)).lineLimit(3)
                    }
                    if item.thread.comments.count > 1 {
                        Text(item.thread.comments.count == 2 ? "1 reply" : "\(item.thread.comments.count - 1) replies")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    if item.thread.isResolved, !controller.commentsAreReadOnly {
                        Button("Re-open") {
                            controller.setThread(item.thread.id, resolved: false)
                            actions.openComment(item.thread.id)
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).stroke(state.selectedCommentID == item.thread.id ? Theme.accent : Theme.divider))
                .contentShape(Rectangle())
                .onTapGesture { actions.openComment(item.thread.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}
