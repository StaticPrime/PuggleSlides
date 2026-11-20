import Foundation

/// A change to a shared document, as its log keeps it: changes made one after another become one, and a change made
/// at the same time as another can be rewritten to follow it.
public protocol SharedChange: Equatable, Sendable {
    var isEmpty: Bool { get }
    /// This change followed by `later`, as one.
    func compose(_ later: Self) -> Self
    /// `other`, made at the same time as this change, rewritten to follow it. With `priority`, this change came first
    /// in the log; without, `other` came first.
    func transform(_ other: Self, priority: Bool) -> Self
    /// The change as bytes, to keep or send.
    var encoded: Data { get }
    init(encoded data: Data) throws
}

/// One change in a shared document's log, at its revision: the log is the document's history, one revision after
/// another, the same on every Mac.
public struct LoggedChange<Change: SharedChange>: Equatable, Sendable {
    public var revision: Int
    /// Tells this change from every other, so a Mac knows its own change when it comes back.
    public var id: String
    /// Who made it: their iCloud identity.
    public var author: String
    public var authorName: String
    public var change: Change

    public init(revision: Int, id: String = UUID().uuidString, author: String, authorName: String, change: Change) {
        self.revision = revision
        self.id = id
        self.author = author
        self.authorName = authorName
        self.change = change
    }
}

/// One Mac's side of editing a shared document along with others, through its log.
///
/// Changes made here go into the log one at a time, each claiming the revision after the last one known here. Changes
/// that others got into the log first come in and are applied here; changes of this Mac's still on their way are
/// rewritten to follow them, as are the incoming changes to fit around them. So every Mac ends up the same.
public final class SyncClient<Change: SharedChange> {
    public let author: String
    public var authorName: String
    /// The last revision of the log that's been applied here.
    public private(set) var revision: Int
    /// The change of this Mac's that's claiming the next revision (or about to).
    public private(set) var outstanding: LoggedChange<Change>?
    /// Changes made here since `outstanding`, to go once it's in.
    public private(set) var buffer: Change?
    /// `outstanding`'s id while it's being sent.
    public private(set) var sending: String?
    /// Changes that came ahead of the ones before them.
    private var early: [Int: LoggedChange<Change>] = [:]

    public init(revision: Int, author: String, authorName: String) {
        self.revision = revision
        self.author = author
        self.authorName = authorName
    }

    /// Whether changes made here aren't all in the log yet.
    public var hasPending: Bool { outstanding != nil || buffer != nil }

    /// Everything made here that isn't in the log yet, as one change.
    public var pending: Change? {
        guard let outstanding else { return buffer }
        return buffer.map { outstanding.change.compose($0) } ?? outstanding.change
    }

    /// A change made here.
    public func local(_ change: Change) {
        guard !change.isEmpty else { return }
        if outstanding == nil {
            outstanding = LoggedChange(revision: revision + 1, author: author, authorName: authorName, change: change)
        } else {
            buffer = buffer.map { $0.compose(change) } ?? change
        }
    }

    /// The change to send next, if one is waiting and none is already on its way.
    public func nextToSend() -> LoggedChange<Change>? {
        guard sending == nil, let outstanding else { return nil }
        sending = outstanding.id
        return outstanding
    }

    /// The change went into the log at the revision it claimed.
    public func sent(_ id: String) {
        if sending == id { sending = nil }
        guard let outstanding, outstanding.id == id else { return }
        confirm(outstanding)
    }

    /// The change couldn't be sent (no connection, say); it's sent again next time.
    public func sendFailed(_ id: String) {
        if sending == id { sending = nil }
    }

    /// Another change took the revision the change claimed. Answers what to apply here; the change follows it.
    public func sendTaken(_ id: String, by existing: LoggedChange<Change>) -> [Change] {
        if sending == id { sending = nil }
        return receive([existing])
    }

    /// Changes from the log, in any order. Answers the changes to make here, in the order to make them.
    public func receive(_ changes: [LoggedChange<Change>]) -> [Change] {
        for change in changes where change.revision > revision { early[change.revision] = change }
        var applied: [Change] = []
        while let next = early.removeValue(forKey: revision + 1) {
            if let mine = outstanding, mine.id == next.id {
                if sending == mine.id { sending = nil }
                confirm(mine)
                continue
            }
            var remote = next.change
            if var mine = outstanding {
                let moved = remote.transform(mine.change, priority: true)
                remote = mine.change.transform(remote, priority: false)
                mine.change = moved
                mine.revision = next.revision + 1
                outstanding = mine
            }
            if let pending = buffer {
                let moved = remote.transform(pending, priority: true)
                remote = pending.transform(remote, priority: false)
                buffer = moved
            }
            revision = next.revision
            applied.append(remote)
        }
        return applied
    }

    /// Whether changes from the log are waiting for one that hasn't come.
    public var isMissingChanges: Bool { !early.isEmpty }

    /// The revisions the changes waiting here need first: from the last one applied to the first that came ahead.
    public var missingRevisions: ClosedRange<Int>? {
        guard let first = early.keys.min(), first > revision + 1 else { return nil }
        return (revision + 1)...(first - 1)
    }

    /// Drops the changes made here that aren't in the log yet, for starting over from a snapshot they can't follow.
    public func discardPending() {
        outstanding = nil
        buffer = nil
        sending = nil
    }

    private func confirm(_ change: LoggedChange<Change>) {
        revision = change.revision
        outstanding = buffer.map { LoggedChange(revision: revision + 1, author: author, authorName: authorName, change: $0) }
        buffer = nil
    }

    /// Starts over from a snapshot of the log at `revision`, dropping whatever was known before it.
    public func reset(to revision: Int) {
        self.revision = revision
        early = early.filter { $0.key > revision }
        if var mine = outstanding {
            mine.revision = revision + 1
            outstanding = mine
        }
    }
}
