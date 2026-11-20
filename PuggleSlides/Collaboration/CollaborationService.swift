import AppKit
import CloudKit
import PuggleSlidesKit

/// A change in a shared presentation's log.
typealias LoggedPresentationChange = LoggedChange<PresentationChange>

/// Whether an error only means iCloud can't be reached for now (no network, iCloud busy), rather than that it turned
/// something down.
nonisolated func isConnectionProblem(_ error: Error) -> Bool {
    guard let error = error as? CKError else { return (error as NSError).domain == NSURLErrorDomain }
    return [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated].contains(error.code)
}

/// Whether presentations can be shared from this copy of PuggleSlides, and as whom.
enum CollaborationStatus: Equatable {
    /// Signed in to iCloud: presentations are shared as this person.
    case ready(me: Collaborator)
    /// Sharing can't be done here, and why, in words for the person.
    case unavailable(String)

    var me: Collaborator? {
        if case let .ready(me) = self { return me }
        return nil
    }
}

nonisolated enum CollaborationError: LocalizedError {
    case unavailable(String)
    case notShared
    case notAllowed
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason): reason
        case .notShared: "The presentation isn’t shared any longer."
        case .notAllowed: "You can’t change this presentation, only comment on it."
        case let .failed(reason): reason
        }
    }
}

/// How a shared presentation stands from the sharing side: who it's shared with, and how.
struct DocumentSharing: Equatable {
    var id: UUID
    var title: String
    var owner: Collaborator
    /// Everyone in it, the owner first.
    var collaborators: [Collaborator]
    var access: LinkAccess
    /// What people who join through the link can do.
    var linkPermission: CollaboratorPermission
    var url: URL?
    /// What this Mac's person can do: always edit, for the owner.
    var myPermission: CollaboratorPermission
    var isMine: Bool
}

/// A presentation someone has shared with this Mac's person.
struct SharedDocumentEntry: Equatable, Identifiable {
    var id: UUID
    var title: String
    var ownerName: String
    /// The owner's iCloud identity, which says where the presentation is kept.
    var ownerID: String
}

/// Why a shared presentation can't be reached any longer.
enum UnavailableReason: Equatable {
    /// Its owner stopped sharing it, or took this person out of it.
    case stopped
    /// This person left it.
    case left
}

/// The result of claiming a revision of a presentation's log for a change.
enum ClaimResult {
    case claimed
    /// Another change had already taken the revision.
    case taken(LoggedPresentationChange)
    /// This person may only comment.
    case notAllowed
    case failed(Error)
}

/// Where shared presentations are kept and passed between people: iCloud, or a stand-in for it in debug runs. Every
/// callback arrives on the main thread.
protocol CollaborationService: AnyObject {
    var status: CollaborationStatus { get }
    /// Whether people are invited through the system's own invitation (Messages, Mail, a link it sends), rather than by
    /// an address typed into PuggleSlides.
    var invitesThroughSystem: Bool { get }
    /// Presentations shared with this person, as last read.
    var sharedWithMe: [SharedDocumentEntry] { get }
    /// `status` changed: signed in or out of iCloud, say.
    var onStatus: (() -> Void)? { get set }
    /// Presentations shared with this person came or went.
    var onSharedWithMeChange: (() -> Void)? { get set }
    /// Something changed in iCloud that open presentations should look at now.
    var onChangesAvailable: (() -> Void)? { get set }

    /// Starts listening for changes, and keeps on.
    func start()

    /// Shares a presentation of this person's for the first time: its zones, its first snapshot, its comments and its
    /// share. Answers with how it's shared.
    func share(_ id: UUID, title: String, snapshot: SyncSnapshot, comments: [SharedComment], access: LinkAccess,
               permission: CollaboratorPermission, completion: @escaping (Result<DocumentSharing, Error>) -> Void)
    func setAccess(_ access: LinkAccess, permission: CollaboratorPermission, of id: UUID,
                   completion: @escaping (Result<DocumentSharing, Error>) -> Void)
    func setPermission(_ permission: CollaboratorPermission, for person: Collaborator, in id: UUID,
                       completion: @escaping (Result<DocumentSharing, Error>) -> Void)
    func remove(_ person: Collaborator, from id: UUID, completion: @escaping (Result<DocumentSharing, Error>) -> Void)
    /// Asks someone to join, at an email address or phone number (where the system doesn't send invitations).
    func invite(_ address: String, permission: CollaboratorPermission, to id: UUID,
                completion: @escaping (Result<DocumentSharing, Error>) -> Void)
    /// Shows the system's invitation to a presentation of this person's, by `view`.
    func showInvitation(for id: UUID, relativeTo view: NSView)
    /// Stops sharing a presentation of this person's: it goes out of iCloud, and from everyone it was shared with.
    func stopSharing(_ id: UUID, completion: @escaping (Error?) -> Void)
    /// Leaves a presentation someone shared with this person.
    func leave(_ id: UUID, completion: @escaping (Error?) -> Void)
    /// Joins a presentation from its invitation link, pasted into PuggleSlides rather than clicked.
    func open(link url: URL, completion: @escaping (Result<SharedDocumentEntry, Error>) -> Void)

    /// Joins the conversation around a shared presentation, this person's or someone else's (`owner`).
    func connect(_ id: UUID, owner: String?, delegate: CollaborationChannelDelegate) -> CollaborationChannel
}

/// One open shared presentation's line to where it's kept: its log, its snapshot, its comments, who's in it.
protocol CollaborationChannel: AnyObject {
    /// Starts reading: how it's shared, the snapshot, the log, comments and presence, then whatever changes.
    func start()
    func stop()
    /// Looks for changes now.
    func fetchSoon()
    /// How often to look for changes while nothing pushes them: often while others are in the presentation.
    var pollInterval: TimeInterval { get set }

    /// Reads the changes at `revisions` again, for a Mac that's missing them. When they can't all be had (long gone, or
    /// unreadable), the presentation's latest snapshot is read afresh instead.
    func fetchChanges(_ revisions: ClosedRange<Int>)

    /// Claims the change's revision of the log for it.
    func claim(_ change: LoggedPresentationChange, completion: @escaping (ClaimResult) -> Void)
    /// Keeps a snapshot of the whole presentation, for people joining later to start from.
    func saveSnapshot(_ snapshot: SyncSnapshot, title: String)
    /// Gives the presentation a new name, for everyone it's shared with (its owner's to do).
    func setTitle(_ title: String)
    /// Saves a comment thread. `base` is the thread as last read, to merge with if someone else changed it meanwhile.
    func save(_ comment: SharedComment, base: CommentThread?, completion: @escaping (Result<SharedComment, Error>) -> Void)
    func deleteComment(_ id: UUID)
    /// Tells the others whether this person has the presentation open, and who they are in it.
    func setPresence(viewing: Bool, isOwner: Bool, permission: CollaboratorPermission)
    /// Leaves a notification for each of `people` (by iCloud identity) whose inbox is known.
    func sendNotice(title: String, body: String, to people: [String])
}

/// What a channel hears.
protocol CollaborationChannelDelegate: AnyObject {
    /// The whole presentation at some revision of the log, as kept for people joining.
    func channel(_ channel: CollaborationChannel, loaded snapshot: SyncSnapshot, info: SharedDocumentInfo)
    /// Changes in the log, in any order, some perhaps known already.
    func channel(_ channel: CollaborationChannel, received changes: [LoggedPresentationChange])
    func channel(_ channel: CollaborationChannel, receivedComments comments: [SharedComment], deleted: [UUID])
    func channel(_ channel: CollaborationChannel, receivedPresence presence: [Presence])
    func channel(_ channel: CollaborationChannel, sharingChanged sharing: DocumentSharing)
    /// Its owner gave it a new name.
    func channel(_ channel: CollaborationChannel, retitled title: String)
    func channel(_ channel: CollaborationChannel, becameUnavailable reason: UnavailableReason)
    /// Whether iCloud answered the latest look for changes (false when it couldn't be reached at all).
    func channel(_ channel: CollaborationChannel, reachable: Bool)
}

extension CollaborationChannelDelegate {
    func channel(_ channel: CollaborationChannel, reachable: Bool) {}
}

/// Sharing in a copy of PuggleSlides that can't reach iCloud for it: every request is turned down, saying why.
final class UnavailableCollaboration: CollaborationService {
    let reason: String
    var onStatus: (() -> Void)?
    var onSharedWithMeChange: (() -> Void)?
    var onChangesAvailable: (() -> Void)?

    init(reason: String) { self.reason = reason }

    var status: CollaborationStatus { .unavailable(reason) }
    var invitesThroughSystem: Bool { true }
    var sharedWithMe: [SharedDocumentEntry] { [] }

    func start() {}

    func share(_ id: UUID, title: String, snapshot: SyncSnapshot, comments: [SharedComment], access: LinkAccess,
               permission: CollaboratorPermission, completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        completion(.failure(CollaborationError.unavailable(reason)))
    }

    func setAccess(_ access: LinkAccess, permission: CollaboratorPermission, of id: UUID,
                   completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        completion(.failure(CollaborationError.unavailable(reason)))
    }

    func setPermission(_ permission: CollaboratorPermission, for person: Collaborator, in id: UUID,
                       completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        completion(.failure(CollaborationError.unavailable(reason)))
    }

    func remove(_ person: Collaborator, from id: UUID, completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        completion(.failure(CollaborationError.unavailable(reason)))
    }

    func invite(_ address: String, permission: CollaboratorPermission, to id: UUID,
                completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        completion(.failure(CollaborationError.unavailable(reason)))
    }

    func showInvitation(for id: UUID, relativeTo view: NSView) {}
    func stopSharing(_ id: UUID, completion: @escaping (Error?) -> Void) { completion(CollaborationError.unavailable(reason)) }
    func leave(_ id: UUID, completion: @escaping (Error?) -> Void) { completion(CollaborationError.unavailable(reason)) }

    func open(link url: URL, completion: @escaping (Result<SharedDocumentEntry, Error>) -> Void) {
        completion(.failure(CollaborationError.unavailable(reason)))
    }

    func connect(_ id: UUID, owner: String?, delegate: CollaborationChannelDelegate) -> CollaborationChannel {
        UnavailableChannel(delegate: delegate)
    }
}

/// A channel that never reaches anything.
private final class UnavailableChannel: CollaborationChannel {
    weak var delegate: CollaborationChannelDelegate?
    var pollInterval: TimeInterval = 15

    init(delegate: CollaborationChannelDelegate) { self.delegate = delegate }

    func start() {}
    func stop() {}
    func fetchSoon() {}
    func fetchChanges(_ revisions: ClosedRange<Int>) {}
    func claim(_ change: LoggedPresentationChange, completion: @escaping (ClaimResult) -> Void) { completion(.failed(CollaborationError.notShared)) }
    func saveSnapshot(_ snapshot: SyncSnapshot, title: String) {}
    func setTitle(_ title: String) {}
    func save(_ comment: SharedComment, base: CommentThread?, completion: @escaping (Result<SharedComment, Error>) -> Void) {
        completion(.failure(CollaborationError.notShared))
    }
    func deleteComment(_ id: UUID) {}
    func setPresence(viewing: Bool, isOwner: Bool, permission: CollaboratorPermission) {}
    func sendNotice(title: String, body: String, to people: [String]) {}
}
