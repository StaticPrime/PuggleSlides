import AppKit
import Observation
import PuggleSlidesKit
import SwiftUI
import UniformTypeIdentifiers

/// What the Collaborate sheet shows and does: a presentation of this person's on its way to being shared, or shared
/// already, with the people in it; or, for a presentation someone shared with them, who's in it and what they can do.
@Observable
final class CollaborateModel {
    @ObservationIgnored let controller: CollaborationController
    @ObservationIgnored private weak var windowController: DocumentWindowController?
    var title: String
    var access: LinkAccess = .invited
    var linkPermission: CollaboratorPermission = .edit
    var isWorking = false
    var problem: String?
    /// Whom to invite, typed in (where the system doesn't send the invitations).
    var address = ""
    var invitePermission: CollaboratorPermission = .edit
    var confirmsStop = false
    var confirmsLeave = false
    @ObservationIgnored var anchor: NSView?
    @ObservationIgnored var done: (() -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// Bumped as iCloud's status changes, so what's shown keeps up.
    private var version = 0

    init(controller: CollaborationController, windowController: DocumentWindowController) {
        self.controller = controller
        self.windowController = windowController
        title = windowController.state.title
        if let sharing = windowController.presentationDocument?.collaboration?.sharing {
            access = sharing.access
            linkPermission = sharing.linkPermission
        }
        observer = NotificationCenter.default.addObserver(forName: .collaborationDidChange, object: controller, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.version += 1 }
        }
    }

    private var document: PresentationDocument? { windowController?.presentationDocument }
    var session: PresentationCollaboration? { document?.collaboration }
    var state: CollaborationState? { windowController?.state.collaboration }

    var status: CollaborationStatus {
        _ = version
        return controller.status
    }

    var isShared: Bool { state?.isShared == true }
    var isOwner: Bool { session?.isOwner ?? true }
    var collaborators: [Collaborator] { state?.collaborators ?? [] }
    var meID: String? { state?.meID ?? status.me?.id }
    var invitesThroughSystem: Bool { controller.service.invitesThroughSystem }
    /// Presentations have to be kept on this Mac before they're shared: that file stays theirs when sharing stops.
    var needsSaving: Bool { document?.fileURL == nil }

    // MARK: Doing it

    /// Shares the presentation; first, if it's never been saved, asks where to keep it on this Mac.
    func share() {
        guard let document, let windowController, let window = windowController.window else { return }
        problem = nil
        guard document.fileURL != nil else {
            saveFirst(document, window: window)
            return
        }
        isWorking = true
        controller.share(document, in: windowController, access: access, permission: linkPermission) { [weak self] error in
            guard let self else { return }
            isWorking = false
            problem = error?.localizedDescription
        }
    }

    private func saveFirst(_ document: PresentationDocument, window: NSWindow) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (title.isEmpty ? "Untitled presentation" : title) + ".pptx"
        panel.allowedContentTypes = [UTType(PresentationFormat.pptx.typeIdentifier) ?? .data]
        panel.message = "Choose where to keep “\(title)” on this Mac. People you share it with work on its copy in iCloud."
        guard let sheet = window.attachedSheet else { return }
        panel.beginSheetModal(for: sheet) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            document.save(to: url, ofType: PresentationFormat.pptx.typeIdentifier, for: .saveAsOperation) { error in
                MainActor.assumeIsolated {
                    if let error {
                        self?.problem = error.localizedDescription
                    } else {
                        self?.share()
                    }
                }
            }
        }
    }

    private func run(_ work: (@escaping (Result<DocumentSharing, Error>) -> Void) -> Void) {
        isWorking = true
        problem = nil
        work { [weak self] result in
            guard let self else { return }
            isWorking = false
            switch result {
            case let .success(sharing): session?.sharingUpdated(sharing)
            case let .failure(error): problem = error.localizedDescription
            }
        }
    }

    func changeAccess(_ access: LinkAccess) {
        self.access = access
        guard isShared, let id = session?.id else { return }
        run { controller.service.setAccess(access, permission: linkPermission, of: id, completion: $0) }
    }

    func changeLinkPermission(_ permission: CollaboratorPermission) {
        linkPermission = permission
        guard isShared, let id = session?.id else { return }
        run { controller.service.setAccess(access, permission: permission, of: id, completion: $0) }
    }

    func setPermission(_ permission: CollaboratorPermission, for person: Collaborator) {
        guard let id = session?.id else { return }
        run { controller.service.setPermission(permission, for: person, in: id, completion: $0) }
    }

    func remove(_ person: Collaborator) {
        guard let id = session?.id else { return }
        run { controller.service.remove(person, from: id, completion: $0) }
    }

    func invite() {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = session?.id, !address.isEmpty else { return }
        self.address = ""
        run { controller.service.invite(address, permission: invitePermission, to: id, completion: $0) }
    }

    func showInvitation() {
        guard let id = session?.id, let anchor else { return }
        controller.service.showInvitation(for: id, relativeTo: anchor)
    }

    func copyLink() {
        guard let url = session?.sharing?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func stopSharing() {
        guard let session else { return }
        isWorking = true
        problem = nil
        controller.stopSharing(session) { [weak self] error in
            guard let self else { return }
            isWorking = false
            if let error {
                problem = error.localizedDescription
            } else {
                done?()
            }
        }
    }

    func leave() {
        guard let session, let windowController else { return }
        isWorking = true
        controller.service.leave(session.id) { [weak self] error in
            guard let self else { return }
            isWorking = false
            if let error {
                problem = error.localizedDescription
                return
            }
            done?()
            session.end()
            windowController.presentationDocument?.close()
        }
    }
}

/// The sheet for sharing a presentation, and for seeing and changing who it's shared with.
struct CollaborateView: View {
    @Bindable var model: CollaborateModel

    var body: some View {
        let shared = model.isShared
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Text(heading).font(.headline)
                    icon
                    Text(model.title.isEmpty ? "Untitled presentation" : model.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    if case let .unavailable(reason) = model.status {
                        Label(reason, systemImage: "exclamationmark.icloud")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if shared {
                        participants
                    }
                    if model.isOwner {
                        accessRow
                        if model.access == .anyoneWithLink { linkPermissionRow }
                        Text(accessExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let me = model.collaborators.first(where: { $0.id == model.meID }) {
                        Text(me.permission == .edit ? "You can edit this presentation and comment on it."
                                                    : "You can see changes as they’re made and add comments, but not change the slides. You can still present it, save a copy or print it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if shared {
                        HStack {
                            if model.session?.sharing?.url != nil {
                                Button { model.copyLink() } label: { Label("Copy Link", systemImage: "link") }
                            }
                            Spacer()
                            if model.isOwner {
                                Button("Stop Sharing…", role: .destructive) { model.confirmsStop = true }
                            } else {
                                Button("Leave…", role: .destructive) { model.confirmsLeave = true }
                            }
                        }
                    }
                    if let problem = model.problem {
                        Text(problem)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                if model.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                if shared {
                    Button("Done") { model.done?() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { model.done?() }
                        .keyboardShortcut(.cancelAction)
                    Button(model.needsSaving ? "Save and Share…" : "Share") { model.share() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isWorking || model.status.me == nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: shared ? 660 : 500)
        .alert("Stop sharing “\(model.title)”?", isPresented: $model.confirmsStop) {
            Button("Stop Sharing", role: .destructive) { model.stopSharing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It closes for everyone it’s shared with and goes out of your iCloud. The presentation stays on this Mac, saved as it is now.")
        }
        .alert("Leave “\(model.title)”?", isPresented: $model.confirmsLeave) {
            Button("Leave", role: .destructive) { model.leave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It closes on this Mac. \(model.state?.ownerName ?? "Its owner") can share it with you again.")
        }
    }

    private var heading: String {
        if !model.isOwner { return "Shared by \(model.state?.ownerName ?? "")" }
        return model.isShared ? "Collaborators" : "Collaborate"
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Color.primary.opacity(0.06))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: model.isShared ? "person.2.fill" : "rectangle.on.rectangle.angled")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
    }

    private var accessRow: some View {
        HStack {
            Text("Who Can Access")
            Spacer()
            Picker("Who Can Access", selection: Binding(get: { model.access }, set: { model.changeAccess($0) })) {
                ForEach(LinkAccess.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var linkPermissionRow: some View {
        HStack {
            Text("People with the Link")
            Spacer()
            Picker("People with the Link", selection: Binding(get: { model.linkPermission }, set: { model.changeLinkPermission($0) })) {
                ForEach(CollaboratorPermission.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var accessExplanation: String {
        let who = model.access == .invited ? "Only people you invite can join, through iCloud on their Mac." : "Anyone with the link can join, through iCloud on their Mac."
        return who + " People who can edit change it along with you as you work; people who can comment see every change and add comments. Everyone can present it, save a copy or print it while it’s shared."
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.collaborators.count == 1 ? "1 Person" : "\(model.collaborators.count) People")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(model.collaborators) { person in
                    participantRow(person, isMe: person.id == model.meID)
                    Divider().padding(.leading, 52)
                }
                if model.isOwner { inviteRow }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
    }

    private func participantRow(_ person: Collaborator, isMe: Bool) -> some View {
        HStack(spacing: 10) {
            CollaboratorBadge(person: person, size: 34, isViewing: model.state?.isViewing(person) ?? false)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName)
                Text(person.isOwner ? "Owner" : (person.status == .invited ? "Invited" : "Joined"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isMe {
                Text("You").foregroundStyle(.secondary)
            } else if person.isOwner {
                EmptyView()
            } else if model.isOwner {
                Picker("Access for \(person.displayName)", selection: Binding(get: { person.permission }, set: { model.setPermission($0, for: person) })) {
                    ForEach(CollaboratorPermission.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button { model.remove(person) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Stop sharing with \(person.displayName)")
                    .accessibilityLabel("Remove \(person.displayName)")
            } else {
                Text(person.permission.displayName).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder private var inviteRow: some View {
        if model.invitesThroughSystem {
            Button { model.showInvitation() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").frame(width: 34, height: 34).background(Circle().fill(Color.primary.opacity(0.08)))
                    Text("Invite Collaborators")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ShareAnchor { model.anchor = $0 })
        } else {
            HStack(spacing: 10) {
                Image(systemName: "plus").frame(width: 34, height: 34).background(Circle().fill(Color.primary.opacity(0.08)))
                TextField("Invite by email or phone", text: $model.address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.invite() }
                Picker("Access", selection: $model.invitePermission) {
                    ForEach(CollaboratorPermission.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button("Invite") { model.invite() }
                    .disabled(model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }
}

/// Hands the view behind it to whoever asks, for the system's invitation to show beside.
private struct ShareAnchor: NSViewRepresentable {
    let found: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { found(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
