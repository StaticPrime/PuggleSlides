import Foundation

/// What someone can do with a presentation shared with them.
public enum CollaboratorPermission: String, Codable, Sendable, CaseIterable {
    /// Edit it along with everyone else, and comment.
    case edit
    /// See it as it changes and comment on it, but not change it.
    case comment

    public var displayName: String {
        switch self {
        case .edit: "Can edit"
        case .comment: "Can comment"
        }
    }

    public var explanation: String {
        switch self {
        case .edit: "Edits the presentation along with you, and comments."
        case .comment: "Sees your changes as you make them and adds comments, but can’t change the slides."
        }
    }
}

/// Who can join a shared presentation: only the people invited, or anyone who has its link.
public enum LinkAccess: String, Codable, Sendable, CaseIterable {
    case invited, anyoneWithLink

    public var displayName: String {
        switch self {
        case .invited: "People You Choose"
        case .anyoneWithLink: "Anyone with the Link"
        }
    }
}

/// Someone a presentation is shared with, or the person who shares it.
public struct Collaborator: Hashable, Codable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        /// Invited, and not yet joined.
        case invited
        case joined
    }

    /// Stays the same however their name shows: their iCloud identity, or the address they were invited at.
    public var id: String
    public var name: String
    /// The email address or phone number iCloud knows them by, when it says.
    public var address: String?
    public var isOwner: Bool
    public var permission: CollaboratorPermission
    public var status: Status

    public init(id: String, name: String, address: String? = nil, isOwner: Bool = false, permission: CollaboratorPermission = .edit,
                status: Status = .joined) {
        self.id = id
        self.name = name
        self.address = address
        self.isOwner = isOwner
        self.permission = permission
        self.status = status
    }

    /// The name to show: their name, else how they were invited.
    public var displayName: String {
        if !name.isEmpty { return name }
        return address ?? "Someone"
    }

    /// Up to two initials, for the round badge: from their name, else their address.
    public var initials: String {
        let words = name.split { $0 == " " || $0 == "-" }.filter { $0.first?.isLetter == true }
        let letters = words.count > 1 ? [words.first!, words.last!].compactMap(\.first) : words.first.map { Array($0.prefix(1)) } ?? []
        if !letters.isEmpty { return String(letters).uppercased() }
        return (address?.first.map { String($0) } ?? "?").uppercased()
    }

    public var roleDescription: String {
        isOwner ? "Owner" : permission.displayName
    }
}

/// How a shared presentation is kept in iCloud.
///
/// Each shared presentation has two zones in its owner's iCloud. The document zone holds a `Document` record (a
/// snapshot of the whole presentation now and then, and what's said about it) and one `Change` record per revision of
/// its log; it's shared with each person as they're allowed, to edit or only to read. The talk zone holds what
/// everyone may add, whatever they can do to the slides: `Comment` records, one per thread, and `Presence` records, one
/// per person, saying who has it open. It's shared so that anyone who can read the presentation can write there,
/// through a link kept in the document zone. And each person has an inbox zone of their own, which the people they work
/// with leave `Notice` records in, a short summary of what they changed, so that iCloud shows a notification.
public enum CollaborationRecords {
    public static let documentType = "Document"
    public static let changeType = "Change"
    public static let commentType = "Comment"
    public static let presenceType = "Presence"
    public static let noticeType = "Notice"

    /// The `Document` record's name.
    public static let documentName = "document"
    public static let infoKey = "info"
    public static let snapshotKey = "snapshot"
    public static let revisionKey = "revision"
    public static let changeKey = "change"
    /// Tells one change from another (see `LoggedChange.id`).
    public static let changeIDKey = "changeID"
    public static let authorKey = "author"
    public static let titleKey = "title"
    public static let bodyKey = "body"
    public static let documentKey = "document"
    public static let ownerKey = "owner"

    static let documentPrefix = "doc-"
    static let talkPrefix = "talk-"
    public static let inboxZone = "inbox"

    public static func documentZone(_ id: UUID) -> String { documentPrefix + id.uuidString }
    public static func talkZone(_ id: UUID) -> String { talkPrefix + id.uuidString }

    /// The presentation a document zone holds, if it's one.
    public static func document(inZone name: String) -> UUID? {
        guard name.hasPrefix(documentPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(documentPrefix.count)))
    }

    /// The presentation a talk zone is for, if it's one.
    public static func document(inTalkZone name: String) -> UUID? {
        guard name.hasPrefix(talkPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(talkPrefix.count)))
    }

    /// The `Change` record of a revision: one name per revision, so only one change can ever take it.
    public static func changeName(_ revision: Int) -> String { String(format: "change-%012d", revision) }

    public static func revision(ofChange name: String) -> Int? {
        guard name.hasPrefix("change-") else { return nil }
        return Int(name.dropFirst("change-".count))
    }

    public static func presenceName(_ person: String) -> String { "presence-" + person }

    /// Sorted keys and exact dates, so the same thing always encodes the same.
    public static func encode(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)) ?? Data()
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// What the `Document` record says about a shared presentation, besides its snapshot.
public struct SharedDocumentInfo: Codable, Equatable, Sendable {
    public var title: String
    /// The owner's name as their Mac knows it, for when iCloud doesn't say.
    public var ownerName: String
    /// The link to the talk zone, for everyone who joins to take part in.
    public var talkURL: URL?
    /// The revision the snapshot is at.
    public var snapshotRevision: Int

    public init(title: String, ownerName: String, talkURL: URL? = nil, snapshotRevision: Int = 0) {
        self.title = title
        self.ownerName = ownerName
        self.talkURL = talkURL
        self.snapshotRevision = snapshotRevision
    }
}

/// A `Comment` record: one thread and the slide it's on.
public struct SharedComment: Codable, Equatable, Sendable {
    public var thread: CommentThread
    public var slideID: UUID

    public init(thread: CommentThread, slideID: UUID) {
        self.thread = thread
        self.slideID = slideID
    }

    /// `thread` as changed here, laid over `server`'s copy of it changed by someone else meanwhile: replies from both,
    /// and the wording, resolution and place from here where here changed them.
    public static func merge(local: CommentThread, base: CommentThread?, server: CommentThread) -> CommentThread {
        var merged = server
        let baseComments = Dictionary((base?.comments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localIDs = Set(local.comments.map(\.id))
        // Comments deleted here go; comments added or edited here join or replace the server's.
        merged.comments.removeAll { baseComments[$0.id] != nil && !localIDs.contains($0.id) }
        for comment in local.comments {
            if let index = merged.comments.firstIndex(where: { $0.id == comment.id }) {
                if baseComments[comment.id] != comment { merged.comments[index] = comment }
            } else if baseComments[comment.id] == nil {
                merged.comments.append(comment)
            }
        }
        // The comment that started the thread stays first; replies follow in the order they were made.
        if let starter = server.comments.first?.id ?? local.comments.first?.id,
           let index = merged.comments.firstIndex(where: { $0.id == starter }) {
            let first = merged.comments.remove(at: index)
            merged.comments = [first] + merged.comments.sorted { $0.date < $1.date }
        }
        if base == nil || base?.isResolved != local.isResolved { merged.isResolved = local.isResolved }
        if base == nil || base?.elementID != local.elementID { merged.elementID = local.elementID }
        if base == nil || base?.position != local.position { merged.position = local.position }
        return merged
    }
}

/// A `Presence` record: someone's name, whether they have the presentation open now, what they can do with it, and
/// their inbox. It's what they say about themselves, so it names them even where iCloud doesn't.
public struct PresenceInfo: Codable, Equatable, Sendable {
    public var name: String
    public var isViewing: Bool
    /// The link to their inbox zone, for notices to them.
    public var inboxURL: URL?
    public var isOwner: Bool?
    public var permission: CollaboratorPermission?

    public init(name: String, isViewing: Bool, inboxURL: URL?, isOwner: Bool? = nil, permission: CollaboratorPermission? = nil) {
        self.name = name
        self.isViewing = isViewing
        self.inboxURL = inboxURL
        self.isOwner = isOwner
        self.permission = permission
    }
}

/// Someone's presence in a presentation, as last heard.
public struct Presence: Equatable, Sendable {
    public var person: String
    public var info: PresenceInfo
    /// When iCloud last had word from them.
    public var date: Date

    public init(person: String, info: PresenceInfo, date: Date) {
        self.person = person
        self.info = info
        self.date = date
    }

    /// How long a presence counts as current without a fresh word.
    public static let freshness: TimeInterval = 150

    public func isActive(now: Date = Date()) -> Bool { info.isViewing && now.timeIntervalSince(date) < Self.freshness }
}
