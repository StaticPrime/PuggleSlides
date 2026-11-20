import AppKit
import CloudKit
import os
import PuggleSlidesKit
import Security

/// What went wrong with iCloud, written to the Mac's own log (Xcode's console shows it), never sent anywhere.
let collaborationLog = Logger(subsystem: "com.pugglesoft.PuggleSlides", category: "Collaboration")

/// Shared presentations through iCloud (see `CollaborationRecords` for how they're kept). Presentations of this
/// person's are zones in their private database, shared with the people they choose; presentations shared with them
/// are read from their shared database. Changes are looked for when iCloud pushes word of them, and every few seconds
/// while other people are in an open presentation.
final class CloudKitCollaboration: NSObject, CollaborationService {
    nonisolated static let containerIdentifier = "iCloud.com.pugglesoft.PuggleSlides"

    /// Whether this copy of PuggleSlides is signed to use the iCloud container shared presentations are kept in. Without
    /// that, iCloud mustn't be touched at all: CloudKit stops an app asking for a container it isn't signed for.
    nonisolated static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains(containerIdentifier) == true
    }

    /// Made only once sharing starts, so nothing reaches for iCloud before it's known to be allowed.
    private(set) lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private let defaults: UserDefaults
    var onStatus: (() -> Void)?
    var onSharedWithMeChange: (() -> Void)?
    var onChangesAvailable: (() -> Void)?
    private(set) var status: CollaborationStatus = .unavailable("Checking iCloud…")
    var invitesThroughSystem: Bool { true }
    private(set) var sharedWithMe: [SharedDocumentEntry] = []
    /// Open documents' channels, by document.
    private var channels: [UUID: WeakChannel] = [:]
    /// The shares of documents of this person's, as last read or saved.
    private var shares: [UUID: CKShare] = [:]
    private var observers: [NSObjectProtocol] = []
    private var isFetching = false
    private var fetchesAgain = false
    private var isSubscribedToInbox = false
    /// The system's invitation while it shows, and the document it's for.
    private var picker: NSSharingServicePicker?
    private var invitingDocument: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Starting and keeping up

    func start() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkAccount() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fetchChanges() }
            },
        ]
        NSApp.registerForRemoteNotifications()
        checkAccount()
    }

    private func checkAccount() {
        Task {
            let status = await accountStatus()
            if status != self.status {
                self.status = status
                onStatus?()
            }
            guard let me = status.me else { return }
            await subscribe(as: me)
            await prepareInbox(as: me)
            fetchChanges()
        }
    }

    private func accountStatus() async -> CollaborationStatus {
        do {
            switch try await container.accountStatus() {
            case .available:
                let id = (try? await container.userRecordID())?.recordName ?? "me"
                return .ready(me: Collaborator(id: id, name: NSFullUserName(), isOwner: true))
            case .noAccount:
                return .unavailable("Sign in to iCloud in System Settings to share presentations.")
            case .restricted:
                return .unavailable("iCloud is restricted on this Mac, so presentations can’t be shared.")
            case .temporarilyUnavailable:
                return .unavailable("iCloud needs your attention in System Settings before presentations can be shared.")
            default:
                return .unavailable("iCloud can’t be reached right now.")
            }
        } catch {
            collaborationLog.error("Checking the iCloud account failed: \(error.localizedDescription, privacy: .public)")
            return .unavailable("iCloud can’t be reached right now.")
        }
    }

    /// Asks iCloud to say (quietly) whenever something shared changes. Asked at every start rather than remembered, so
    /// subscriptions iCloud lost, or made for its other environment by a build from Xcode, are made again.
    private func subscribe(as me: Collaborator) async {
        do {
            for (database, name) in [(container.sharedCloudDatabase, "shared-changes"), (container.privateCloudDatabase, "private-changes")] {
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                let subscription = CKDatabaseSubscription(subscriptionID: name)
                subscription.notificationInfo = info
                let result = try await database.modifySubscriptions(saving: [subscription], deleting: [])
                _ = try result.saveResults[name]?.get()
            }
        } catch {
            // Asked again next time PuggleSlides opens; open documents look for changes as they go.
            collaborationLog.error("Subscribing to changes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A push from iCloud: something shared has changed.
    func receivedPush(_ userInfo: [String: Any]) {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo),
              note.containerIdentifier == Self.containerIdentifier else { return }
        fetchChanges()
    }

    /// Reads which documents are shared with this person, and tells open documents to look for changes.
    func fetchChanges() {
        for channel in channels.values { channel.channel?.fetchSoon() }
        onChangesAvailable?()
        guard status.me != nil else { return }
        guard !isFetching else {
            fetchesAgain = true
            return
        }
        isFetching = true
        Task {
            await fetchShared()
            await fetchMine()
            if let me = status.me { await subscribeToInbox(as: me) }
            isFetching = false
            if fetchesAgain {
                fetchesAgain = false
                fetchChanges()
            }
        }
    }

    private func token(_ name: String) -> CKServerChangeToken? {
        guard let me = status.me, let data = defaults.data(forKey: "CollaborationToken-\(name)-\(me.id)") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func setToken(_ token: CKServerChangeToken?, _ name: String) {
        guard let me = status.me else { return }
        let key = "CollaborationToken-\(name)-\(me.id)"
        if let token, let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func changes(in database: CKDatabase, since token: CKServerChangeToken?) async throws
        -> (changed: [CKRecordZone.ID], deleted: [CKRecordZone.ID], token: CKServerChangeToken) {
        var changed: [CKRecordZone.ID] = []
        var deleted: [CKRecordZone.ID] = []
        var token = token
        while true {
            let result = try await database.databaseChanges(since: token)
            changed += result.modifications.map(\.zoneID)
            deleted += result.deletions.map(\.zoneID)
            token = result.changeToken
            if !result.moreComing { return (changed.filter { !deleted.contains($0) }, deleted, result.changeToken) }
        }
    }

    /// Documents shared with this person: new ones are read, gone ones go, from their open windows too.
    private func fetchShared() async {
        let since = token("shared")
        let found: (changed: [CKRecordZone.ID], deleted: [CKRecordZone.ID], token: CKServerChangeToken)
        do {
            found = try await changes(in: container.sharedCloudDatabase, since: since)
        } catch let error as CKError where error.code == .changeTokenExpired {
            setToken(nil, "shared")
            fetchesAgain = true
            return
        } catch {
            return
        }
        var entries = since == nil ? [] : sharedWithMe
        var changed = false
        for zone in found.deleted {
            guard let id = CollaborationRecords.document(inZone: zone.zoneName) else { continue }
            entries.removeAll { $0.id == id }
            changed = true
            channels[id]?.channel?.zoneWentAway()
        }
        for zone in found.changed {
            guard let id = CollaborationRecords.document(inZone: zone.zoneName) else { continue }
            let recordID = CKRecord.ID(recordName: CollaborationRecords.documentName, zoneID: zone)
            guard let records = try? await container.sharedCloudDatabase.records(for: [recordID], desiredKeys: [CollaborationRecords.infoKey]),
                  case let .success(record)? = records[recordID],
                  let info = CollaborationRecords.decode(SharedDocumentInfo.self, from: record[CollaborationRecords.infoKey] as? Data)
            else { continue }
            let entry = SharedDocumentEntry(id: id, title: info.title, ownerName: info.ownerName, ownerID: zone.ownerName)
            if let index = entries.firstIndex(where: { $0.id == id }) { entries[index] = entry } else { entries.append(entry) }
            changed = true
        }
        setToken(found.token, "shared")
        if changed || since == nil {
            sharedWithMe = entries.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            onSharedWithMeChange?()
        }
    }

    /// Documents of this person's whose zones went (sharing stopped from another of their Macs).
    private func fetchMine() async {
        let since = token("private")
        do {
            let found = try await changes(in: container.privateCloudDatabase, since: since)
            for zone in found.deleted {
                guard let id = CollaborationRecords.document(inZone: zone.zoneName) else { continue }
                shares[id] = nil
                channels[id]?.channel?.zoneWentAway()
            }
            setToken(found.token, "private")
        } catch let error as CKError where error.code == .changeTokenExpired {
            setToken(nil, "private")
        } catch {}
    }

    // MARK: Documents of this person's, shared

    private static func zone(_ name: String, owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: name, ownerName: owner)
    }

    nonisolated static func shareID(in zone: CKRecordZone.ID) -> CKRecord.ID { CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone) }

    func share(_ id: UUID, title: String, snapshot: SyncSnapshot, comments: [SharedComment], access: LinkAccess,
               permission: CollaboratorPermission, completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        Task {
            do {
                guard let me = status.me else { throw CollaborationError.unavailable(Self.reason(status)) }
                let database = container.privateCloudDatabase
                let documentZone = Self.zone(CollaborationRecords.documentZone(id))
                let talkZone = Self.zone(CollaborationRecords.talkZone(id))
                let made = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: documentZone), CKRecordZone(zoneID: talkZone)], deleting: [])
                for result in made.saveResults.values { _ = try result.get() }
                // The talk zone first: anyone with its link (which only people in the document can read) can write
                // there, comments and presence.
                let talkShare = CKShare(recordZoneID: talkZone)
                talkShare.publicPermission = .readWrite
                talkShare[CKShare.SystemFieldKey.title] = "Comments on “\(title)”"
                var records: [CKRecord] = [talkShare]
                for comment in comments { records.append(Self.commentRecord(comment, in: talkZone)) }
                let savedTalk = try await retrying { try await database.modifyRecords(saving: records, deleting: []) }
                guard let talk = try savedTalk.saveResults[talkShare.recordID]?.get() as? CKShare, let talkURL = talk.url else {
                    throw CollaborationError.failed("The presentation couldn’t be shared. Try again in a little while.")
                }
                let info = SharedDocumentInfo(title: title, ownerName: me.name, talkURL: talkURL, snapshotRevision: snapshot.revision)
                let document = try Self.documentRecord(info: info, snapshot: snapshot, in: documentZone)
                let share = CKShare(recordZoneID: documentZone)
                share[CKShare.SystemFieldKey.title] = title
                share.publicPermission = Self.permission(access, permission)
                let saved = try await retrying { try await database.modifyRecords(saving: [document, share], deleting: []) }
                guard let savedShare = try saved.saveResults[share.recordID]?.get() as? CKShare else {
                    throw CollaborationError.failed("The presentation couldn’t be shared. Try again in a little while.")
                }
                shares[id] = savedShare
                completion(.success(sharing(of: id, title: title, share: savedShare, mine: true)))
            } catch {
                collaborationLog.error("Sharing a document failed: \(error.localizedDescription, privacy: .public)")
                completion(.failure(Self.problem(error)))
            }
        }
    }

    /// The share of a document of this person's, as last read or saved, else as iCloud holds it.
    private func existingShare(of id: UUID) async throws -> CKShare? {
        if let share = shares[id] { return share }
        do {
            let share = try await container.privateCloudDatabase.record(for: Self.shareID(in: Self.zone(CollaborationRecords.documentZone(id)))) as? CKShare
            shares[id] = share
            return share
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Changes the share of a document of this person's and saves it; a share changed in iCloud meanwhile (someone
    /// joined, say) is read again and changed afresh.
    private func changeShare(of id: UUID, _ change: (CKShare) -> Void) async throws -> CKShare {
        for attempt in 0..<2 {
            if attempt > 0 { shares[id] = nil }
            guard let share = try await existingShare(of: id) else { throw CollaborationError.notShared }
            change(share)
            do {
                let result = try await retrying { try await self.container.privateCloudDatabase.modifyRecords(saving: [share], deleting: []) }
                guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else { break }
                shares[id] = saved
                return saved
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
        throw CollaborationError.failed("The presentation’s sharing couldn’t be changed. Try again in a little while.")
    }

    private func run(_ id: UUID, title: String? = nil, _ completion: @escaping (Result<DocumentSharing, Error>) -> Void,
                     _ work: @escaping () async throws -> CKShare) {
        Task {
            do {
                let share = try await work()
                completion(.success(sharing(of: id, title: title ?? (share[CKShare.SystemFieldKey.title] as? String ?? ""), share: share, mine: true)))
            } catch {
                collaborationLog.error("Changing a document's sharing failed: \(error.localizedDescription, privacy: .public)")
                completion(.failure(Self.problem(error)))
            }
        }
    }

    func setAccess(_ access: LinkAccess, permission: CollaboratorPermission, of id: UUID,
                   completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        run(id, completion) { try await self.changeShare(of: id) { $0.publicPermission = Self.permission(access, permission) } }
    }

    func setPermission(_ permission: CollaboratorPermission, for person: Collaborator, in id: UUID,
                       completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        run(id, completion) {
            try await self.changeShare(of: id) { share in
                for participant in share.participants where participant.role != .owner && Self.matches(participant, person) {
                    participant.permission = permission == .edit ? .readWrite : .readOnly
                }
            }
        }
    }

    func remove(_ person: Collaborator, from id: UUID, completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        run(id, completion) {
            let share = try await self.changeShare(of: id) { share in
                for participant in share.participants where participant.role != .owner && Self.matches(participant, person) {
                    share.removeParticipant(participant)
                }
            }
            // And from the talk zone, so they can't read the comments any longer either.
            let talk = Self.shareID(in: Self.zone(CollaborationRecords.talkZone(id)))
            if let talkShare = try? await self.container.privateCloudDatabase.record(for: talk) as? CKShare {
                for participant in talkShare.participants where participant.role != .owner && Self.matches(participant, person) {
                    talkShare.removeParticipant(participant)
                }
                _ = try? await self.container.privateCloudDatabase.modifyRecords(saving: [talkShare], deleting: [])
            }
            return share
        }
    }

    /// Adds someone by email address or phone number. They're told by the link, which the system's invitation sends;
    /// this is for when it isn't used.
    func invite(_ address: String, permission: CollaboratorPermission, to id: UUID,
                completion: @escaping (Result<DocumentSharing, Error>) -> Void) {
        run(id, completion) {
            let person = address.contains("@") ? try await self.container.shareParticipant(forEmailAddress: address)
                                                : try await self.container.shareParticipant(forPhoneNumber: address)
            person.permission = permission == .edit ? .readWrite : .readOnly
            return try await self.changeShare(of: id) { $0.addParticipant(person) }
        }
    }

    /// Stops sharing a document of this person's by deleting its zones: the shares go, and with them the document
    /// from everyone's Mac.
    func stopSharing(_ id: UUID, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                let zones = [Self.zone(CollaborationRecords.documentZone(id)), Self.zone(CollaborationRecords.talkZone(id))]
                let result = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: zones)
                for outcome in result.deleteResults.values {
                    do {
                        try outcome.get()
                    } catch let error as CKError where error.code == .zoneNotFound {
                        // Gone already.
                    }
                }
            } catch let error as CKError where error.code == .zoneNotFound {
                // Not in iCloud already.
            } catch {
                collaborationLog.error("Stopping sharing failed: \(error.localizedDescription, privacy: .public)")
                completion(Self.problem(error))
                return
            }
            shares[id] = nil
            completion(nil)
        }
    }

    /// Leaves a document shared with this person: taking its shares from their shared database takes them out.
    func leave(_ id: UUID, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                let database = container.sharedCloudDatabase
                let zones = try await database.allRecordZones().map(\.zoneID).filter {
                    CollaborationRecords.document(inZone: $0.zoneName) == id || CollaborationRecords.document(inTalkZone: $0.zoneName) == id
                }
                for zone in zones {
                    do {
                        let result = try await database.modifyRecords(saving: [], deleting: [Self.shareID(in: zone)])
                        try result.deleteResults[Self.shareID(in: zone)]?.get()
                    } catch {
                        let result = try await database.modifyRecordZones(saving: [], deleting: [zone])
                        try result.deleteResults[zone]?.get()
                    }
                }
                sharedWithMe.removeAll { $0.id == id }
                onSharedWithMeChange?()
                completion(nil)
            } catch {
                collaborationLog.error("Leaving a document failed: \(error.localizedDescription, privacy: .public)")
                completion(Self.problem(error))
            }
        }
    }

    /// Gives the share of a document of this person's its new name.
    func retitleShare(of id: UUID, to title: String) async {
        _ = try? await changeShare(of: id) { $0[CKShare.SystemFieldKey.title] = title }
    }

    // MARK: The system's invitation

    /// Shows the system's invitation to a document of this person's, which sends its link by Messages, Mail or
    /// AirDrop, or copies it, and lets them choose whether the people they invite can edit or only comment.
    func showInvitation(for id: UUID, relativeTo view: NSView) {
        Task {
            guard let share = try? await existingShare(of: id) else { return }
            let provider = NSItemProvider()
            let access: CKSharingParticipantAccessOption = share.publicPermission == .none ? .specifiedRecipientsOnly : .anyoneWithLink
            provider.registerCKShare(share, container: container,
                                     allowedSharingOptions: CKAllowedSharingOptions(allowedParticipantPermissionOptions: .any,
                                                                                    allowedParticipantAccessOptions: access))
            let picker = NSSharingServicePicker(items: [provider])
            picker.delegate = self
            self.picker = picker
            invitingDocument = id
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
    }

    /// Reads a document's share again, once the invitation's been sent, to show who's been invited.
    private func refreshShare(of id: UUID) {
        Task {
            shares[id] = nil
            guard let share = try? await existingShare(of: id) else { return }
            channels[id]?.channel?.sharingChanged(share)
        }
    }

    // MARK: Joining documents shared with this person

    /// Joins a document someone shared, from the link they sent, and its talk zone through the link kept in it.
    func accept(_ metadata: CKShare.Metadata, completion: @escaping (Result<SharedDocumentEntry, Error>) -> Void) {
        Task {
            do {
                let zone = metadata.share.recordID.zoneID
                guard metadata.containerIdentifier == Self.containerIdentifier, let id = CollaborationRecords.document(inZone: zone.zoneName) else {
                    throw CollaborationError.failed("That link isn’t to a presentation shared from PuggleSlides.")
                }
                let title = metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Shared presentation"
                if metadata.participantRole == .owner {
                    completion(.success(SharedDocumentEntry(id: id, title: title, ownerName: status.me?.name ?? "", ownerID: CKCurrentUserDefaultName)))
                    return
                }
                if metadata.participantStatus != .accepted { _ = try await container.accept(metadata) }
                let info = try await documentInfo(in: zone)
                if let talkURL = info?.talkURL { _ = try? await joinTalk(talkURL) }
                let entry = SharedDocumentEntry(id: id, title: info?.title ?? title, ownerName: info?.ownerName ?? "", ownerID: zone.ownerName)
                if !sharedWithMe.contains(where: { $0.id == id }) {
                    sharedWithMe.append(entry)
                    onSharedWithMeChange?()
                }
                completion(.success(entry))
            } catch {
                collaborationLog.error("Joining a shared document failed: \(error.localizedDescription, privacy: .public)")
                completion(.failure(Self.problem(error)))
            }
        }
    }

    /// Joins a document from its invitation link, pasted in: for when clicking the link opens it in a browser.
    func open(link url: URL, completion: @escaping (Result<SharedDocumentEntry, Error>) -> Void) {
        Task {
            do {
                let metadata = try await container.shareMetadata(for: url)
                accept(metadata, completion: completion)
            } catch let error as CKError where [.unknownItem, .permissionFailure].contains(error.code) {
                collaborationLog.error("Opening an invitation link failed: \(error.localizedDescription, privacy: .public)")
                completion(.failure(CollaborationError.failed("That link doesn’t open for the Apple ID this Mac is signed in to iCloud with. Ask whoever shared it to invite that Apple ID, or to share it with Anyone with the Link.")))
            } catch {
                collaborationLog.error("Opening an invitation link failed: \(error.localizedDescription, privacy: .public)")
                completion(.failure(Self.problem(error)))
            }
        }
    }

    private func documentInfo(in zone: CKRecordZone.ID) async throws -> SharedDocumentInfo? {
        let recordID = CKRecord.ID(recordName: CollaborationRecords.documentName, zoneID: zone)
        let records = try await container.sharedCloudDatabase.records(for: [recordID], desiredKeys: [CollaborationRecords.infoKey])
        guard case let .success(record)? = records[recordID] else { return nil }
        return CollaborationRecords.decode(SharedDocumentInfo.self, from: record[CollaborationRecords.infoKey] as? Data)
    }

    /// Joins a zone shared through a link that lets anyone with it write there: a document's talk zone, or someone's
    /// inbox. Answers where it is in the shared database.
    @discardableResult
    func joinTalk(_ url: URL) async throws -> CKRecordZone.ID {
        let metadata = try await container.shareMetadata(for: url)
        if metadata.participantStatus != .accepted, metadata.participantRole != .owner { _ = try await container.accept(metadata) }
        return metadata.share.recordID.zoneID
    }

    // MARK: Inboxes

    /// This person's inbox: made once, shared so that the people they work with can leave notices in it, with a
    /// subscription that shows each notice as a notification.
    private(set) var inboxURL: URL?

    private func prepareInbox(as me: Collaborator) async {
        let key = "CollaborationInbox-\(me.id)"
        let database = container.privateCloudDatabase
        let zone = Self.zone(CollaborationRecords.inboxZone)
        do {
            // The inbox's link as iCloud has it now, not as remembered: one remembered from a build that used iCloud's
            // other environment, or from before the inbox was made again, leads nowhere.
            guard let url = (try await database.record(for: Self.shareID(in: zone)) as? CKShare)?.url else { return }
            defaults.set(url, forKey: key)
            inboxURL = url
        } catch let error as CKError where [.zoneNotFound, .unknownItem].contains(error.code) {
            do {
                let made = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
                _ = try made.saveResults[zone]?.get()
                let share = CKShare(recordZoneID: zone)
                share.publicPermission = .readWrite
                share[CKShare.SystemFieldKey.title] = "PuggleSlides notices for \(me.name)"
                let saved = try await database.modifyRecords(saving: [share], deleting: [])
                guard let url = (try saved.saveResults[share.recordID]?.get() as? CKShare)?.url else { return }
                defaults.set(url, forKey: key)
                inboxURL = url
            } catch {
                // Tried again next time PuggleSlides opens; until then nobody can leave notices for this person.
                collaborationLog.error("Making the inbox for notices failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        } catch {
            // iCloud can't be reached just now: the link from last time does meanwhile.
            guard let saved = defaults.url(forKey: key) else {
                collaborationLog.error("Reading the inbox for notices failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            inboxURL = saved
        }
        await subscribeToInbox(as: me)
        await cleanInbox()
    }

    /// Asks iCloud to show each notice left in this person's inbox as a notification. In iCloud's development
    /// environment that can only be asked once a notice has been left there (which adds the kind of record), so
    /// until it's done it's asked again at every look for changes.
    private func subscribeToInbox(as me: Collaborator) async {
        // Made once each time PuggleSlides runs, not remembered, for the same reason as the other subscriptions.
        guard inboxURL != nil, !isSubscribedToInbox else { return }
        do {
            let subscription = CKQuerySubscription(recordType: CollaborationRecords.noticeType, predicate: NSPredicate(value: true),
                                                   subscriptionID: "notices", options: [.firesOnRecordCreation])
            subscription.zoneID = Self.zone(CollaborationRecords.inboxZone)
            let info = CKSubscription.NotificationInfo()
            info.titleLocalizationKey = "NOTICE_TITLE"
            info.titleLocalizationArgs = [CollaborationRecords.titleKey]
            info.alertLocalizationKey = "NOTICE_BODY"
            info.alertLocalizationArgs = [CollaborationRecords.bodyKey]
            info.soundName = "default"
            info.desiredKeys = [CollaborationRecords.documentKey, CollaborationRecords.ownerKey]
            subscription.notificationInfo = info
            let subscribed = try await container.privateCloudDatabase.modifySubscriptions(saving: [subscription], deleting: [])
            _ = try subscribed.saveResults["notices"]?.get()
            isSubscribedToInbox = true
        } catch {
            collaborationLog.notice("Notifications for notices aren't set up yet: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Notices are only for showing; old ones go.
    private func cleanInbox() async {
        let database = container.privateCloudDatabase
        let zone = Self.zone(CollaborationRecords.inboxZone)
        var token: CKServerChangeToken?
        var old: [CKRecord.ID] = []
        do {
            while true {
                let changes = try await database.recordZoneChanges(inZoneWith: zone, since: token, desiredKeys: [])
                for case let .success(modification) in changes.modificationResultsByID.values {
                    let record = modification.record
                    if record.recordType == CollaborationRecords.noticeType, (record.creationDate ?? Date()) < Date().addingTimeInterval(-2 * 86_400) {
                        old.append(record.recordID)
                    }
                }
                token = changes.changeToken
                if !changes.moreComing { break }
            }
            if !old.isEmpty { _ = try await database.modifyRecords(saving: [], deleting: Array(old.prefix(400))) }
        } catch {}
    }

    /// Leaves a notice in someone's inbox, joining it first if this person hasn't before.
    func deliver(title: String, body: String, document: UUID, owner: String, to inbox: URL) async {
        guard let me = status.me, inbox != inboxURL else { return }
        let key = "CollaborationInboxZone-\(me.id)-\(inbox.absoluteString)"
        var zone: CKRecordZone.ID?
        if let saved = defaults.stringArray(forKey: key), saved.count == 2 { zone = CKRecordZone.ID(zoneName: saved[0], ownerName: saved[1]) }
        do {
            if zone == nil {
                let joined = try await joinTalk(inbox)
                zone = joined
                defaults.set([joined.zoneName, joined.ownerName], forKey: key)
            }
            guard let zone else { return }
            let record = CKRecord(recordType: CollaborationRecords.noticeType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
            record[CollaborationRecords.titleKey] = String(title.prefix(100))
            record[CollaborationRecords.bodyKey] = String(body.prefix(100))
            record[CollaborationRecords.documentKey] = document.uuidString
            record[CollaborationRecords.ownerKey] = owner
            record[CollaborationRecords.authorKey] = me.id
            _ = try await retrying { try await self.container.sharedCloudDatabase.modifyRecords(saving: [record], deleting: []) }
        } catch let error as CKError where [.zoneNotFound, .unknownItem, .permissionFailure].contains(error.code) {
            // Their inbox went (they reset it): joined afresh next time.
            defaults.removeObject(forKey: key)
        } catch {
            collaborationLog.error("Leaving a notice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Channels

    func connect(_ id: UUID, owner: String?, delegate: CollaborationChannelDelegate) -> CollaborationChannel {
        let channel = CloudKitChannel(service: self, id: id, owner: owner, delegate: delegate)
        channels[id] = WeakChannel(channel: channel)
        return channel
    }

    func disconnect(_ id: UUID) { channels[id] = nil }

    /// How a document stands from its share.
    func sharing(of id: UUID, title: String, share: CKShare, mine: Bool) -> DocumentSharing {
        let people = share.participants.compactMap { person($0, in: share) }
        let owner = people.first(where: \.isOwner) ?? Collaborator(id: share.recordID.zoneID.ownerName, name: "", isOwner: true)
        let me = share.currentUserParticipant
        let myPermission: CollaboratorPermission = mine || me?.role == .owner ? .edit : (me?.permission == .readWrite ? .edit : .comment)
        return DocumentSharing(id: id, title: title, owner: owner, collaborators: people.filter(\.isOwner) + people.filter { !$0.isOwner },
                               access: share.publicPermission == .none ? .invited : .anyoneWithLink,
                               linkPermission: share.publicPermission == .readWrite ? .edit : .comment,
                               url: share.url, myPermission: myPermission, isMine: mine)
    }

    private func person(_ participant: CKShare.Participant, in share: CKShare) -> Collaborator? {
        guard participant.acceptanceStatus != .removed else { return nil }
        let identity = participant.userIdentity
        let isMe = participant == share.currentUserParticipant
        var name = identity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
        if name.isEmpty, isMe { name = status.me?.name ?? "" }
        let isOwner = participant.role == .owner
        return Collaborator(id: isMe ? (status.me?.id ?? Self.id(of: participant)) : Self.id(of: participant), name: name,
                            address: identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber, isOwner: isOwner,
                            permission: isOwner || participant.permission == .readWrite ? .edit : .comment,
                            status: isOwner || participant.acceptanceStatus == .accepted ? .joined : .invited)
    }

    /// How someone in a share is known however their name shows: their iCloud identity, or the address they were
    /// invited at.
    private static func id(of participant: CKShare.Participant) -> String {
        let identity = participant.userIdentity
        if let record = identity.userRecordID?.recordName, record != CKCurrentUserDefaultName { return record }
        return identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber ?? identity.lookupInfo?.userRecordID?.recordName ?? "someone"
    }

    private static func matches(_ participant: CKShare.Participant, _ person: Collaborator) -> Bool {
        let lookup = participant.userIdentity.lookupInfo
        return id(of: participant) == person.id
            || (person.address != nil && (lookup?.emailAddress == person.address || lookup?.phoneNumber == person.address))
    }

    private static func permission(_ access: LinkAccess, _ permission: CollaboratorPermission) -> CKShare.ParticipantPermission {
        access == .invited ? .none : (permission == .edit ? .readWrite : .readOnly)
    }

    // MARK: Records

    nonisolated static func documentRecord(info: SharedDocumentInfo, snapshot: SyncSnapshot, in zone: CKRecordZone.ID,
                                           existing: CKRecord? = nil) throws -> CKRecord {
        let record = existing ?? CKRecord(recordType: CollaborationRecords.documentType,
                                          recordID: CKRecord.ID(recordName: CollaborationRecords.documentName, zoneID: zone))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString)")
        try snapshot.encoded.write(to: file)
        record[CollaborationRecords.infoKey] = CollaborationRecords.encode(info)
        record[CollaborationRecords.revisionKey] = snapshot.revision
        record[CollaborationRecords.snapshotKey] = CKAsset(fileURL: file)
        return record
    }

    nonisolated static func commentRecord(_ comment: SharedComment, in zone: CKRecordZone.ID, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: CollaborationRecords.commentType, recordID: CKRecord.ID(recordName: comment.thread.id.uuidString, zoneID: zone))
        record[CollaborationRecords.infoKey] = CollaborationRecords.encode(comment)
        return record
    }

    /// Runs `work`, and once more after the pause iCloud asks for when it's busy or the network dropped.
    func retrying<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as CKError where [.serviceUnavailable, .requestRateLimited, .zoneBusy, .networkFailure].contains(error.code) {
            try await Task.sleep(for: .seconds(error.retryAfterSeconds ?? 3))
            return try await work()
        }
    }

    static func reason(_ status: CollaborationStatus) -> String {
        if case let .unavailable(reason) = status { return reason }
        return "The presentation couldn’t be shared."
    }

    /// Words for the person about what went wrong.
    nonisolated static func problem(_ error: Error) -> Error {
        guard let error = error as? CKError else { return error }
        switch error.code {
        case .notAuthenticated:
            return CollaborationError.failed("Sign in to iCloud in System Settings to share presentations.")
        case .quotaExceeded:
            return CollaborationError.failed("Your iCloud storage is full. Free up some space, or choose more in System Settings.")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return CollaborationError.failed("iCloud can’t be reached right now. Try again in a little while.")
        case .tooManyParticipants:
            return CollaborationError.failed("The presentation is shared with as many people as iCloud allows.")
        case .participantMayNeedVerification:
            return CollaborationError.failed("iCloud needs to check it’s you. Open the link again from the message it came in.")
        case .permissionFailure:
            return CollaborationError.notAllowed
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            return CollaborationError.notShared
        case .partialFailure:
            if let first = error.partialErrorsByItemID?.values.first { return problem(first) }
            return CollaborationError.failed(error.localizedDescription)
        default:
            return CollaborationError.failed(error.localizedDescription)
        }
    }
}

extension CloudKitCollaboration: NSSharingServicePickerDelegate, NSCloudSharingServiceDelegate {
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { picker = nil }
    }

    func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) {
        guard let id = invitingDocument else { return }
        shares[id] = share
        channels[id]?.channel?.sharingChanged(share)
    }

    func sharingService(_ sharingService: NSSharingService, didStopSharing share: CKShare) {
        guard let id = invitingDocument else { return }
        stopSharing(id) { [weak self] error in
            if error == nil { self?.channels[id]?.channel?.zoneWentAway() }
        }
    }

    func sharingService(_ sharingService: NSSharingService, didCompleteForItems items: [Any], error: (any Error)?) {
        picker = nil
        if let id = invitingDocument { refreshShare(of: id) }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        picker = nil
        if let id = invitingDocument { refreshShare(of: id) }
    }
}

private struct WeakChannel {
    weak var channel: CloudKitChannel?
}

// MARK: - One document's channel

/// One open shared document's line to iCloud: its document zone (snapshot, log, share) and talk zone (comments,
/// presence), read as they change.
final class CloudKitChannel: CollaborationChannel {
    private unowned let service: CloudKitCollaboration
    private weak var delegate: CollaborationChannelDelegate?
    let id: UUID
    /// Whose iCloud the document is in; nil for this person's own.
    private let owner: String?
    private var documentZone: CKRecordZone.ID
    private var talkZone: CKRecordZone.ID?
    private var tokens: [CKRecordZone.ID: CKServerChangeToken] = [:]
    private var documentRecord: CKRecord?
    private var info: SharedDocumentInfo?
    private var comments: [UUID: CKRecord] = [:]
    private var presence: [String: PresenceInfo] = [:]
    private var isRunning = false
    private var isFetching = false
    private var fetchesAgain = false
    private var timer: Timer?
    private var lastGarbageRevision = 0
    var pollInterval: TimeInterval = 15 {
        didSet { if pollInterval != oldValue { schedulePolling() } }
    }

    init(service: CloudKitCollaboration, id: UUID, owner: String?, delegate: CollaborationChannelDelegate) {
        self.service = service
        self.id = id
        self.owner = owner
        self.delegate = delegate
        documentZone = CKRecordZone.ID(zoneName: CollaborationRecords.documentZone(id), ownerName: owner ?? CKCurrentUserDefaultName)
        if owner == nil {
            talkZone = CKRecordZone.ID(zoneName: CollaborationRecords.talkZone(id), ownerName: CKCurrentUserDefaultName)
        }
    }

    private var database: CKDatabase { owner == nil ? service.container.privateCloudDatabase : service.container.sharedCloudDatabase }

    func start() {
        isRunning = true
        schedulePolling()
        fetchSoon()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        service.disconnect(id)
    }

    private func schedulePolling() {
        timer?.invalidate()
        guard isRunning else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchSoon() }
        }
    }

    func fetchSoon() {
        guard isRunning else { return }
        guard !isFetching else {
            fetchesAgain = true
            return
        }
        isFetching = true
        Task {
            await fetch()
            isFetching = false
            if fetchesAgain, isRunning {
                fetchesAgain = false
                fetchSoon()
            }
        }
    }

    /// The zone went from iCloud: the document isn't shared any longer.
    func zoneWentAway() {
        guard isRunning else { return }
        stop()
        delegate?.channel(self, becameUnavailable: .stopped)
    }

    func sharingChanged(_ share: CKShare) {
        // What iCloud says about who's in it: with names, addresses and identities or without them.
        let people = share.participants.map { participant -> String in
            let identity = participant.userIdentity
            return "\(participant.role == .owner ? "owner" : "participant") (name \(identity.nameComponents != nil ? "yes" : "no"), "
                + "address \(identity.lookupInfo != nil ? "yes" : "no"), identity \(identity.userRecordID != nil ? "yes" : "no"))"
        }
        collaborationLog.notice("The share lists \(people.count) people: \(people.joined(separator: "; "), privacy: .public)")
        delegate?.channel(self, sharingChanged: service.sharing(of: id, title: info?.title ?? "", share: share, mine: owner == nil))
    }

    // MARK: Reading

    private func fetch() async {
        do {
            if documentRecord == nil { try await loadDocument() }
            try await fetchDocumentZone()
            delegate?.channel(self, reachable: true)
        } catch {
            if isConnectionProblem(error) { delegate?.channel(self, reachable: false) }
            guard carriesOn(after: error, in: documentZone) else { return }
        }
        // Comments and who's here are read even when the log couldn't be, this time.
        guard isRunning, documentRecord != nil else { return }
        _ = await joinedTalkZone()
        do {
            try await fetchTalkZone()
        } catch {
            if let talkZone { _ = carriesOn(after: error, in: talkZone) }
        }
    }

    /// What a failed read means: the presentation went (answers false), the place reached in a zone's changes expired
    /// (it's read again from the start), or something passing (tried again at the next look).
    private func carriesOn(after error: Error, in zone: CKRecordZone.ID) -> Bool {
        if let error = error as? CKError {
            if zone == documentZone, [.zoneNotFound, .userDeletedZone].contains(error.code) || (error.code == .unknownItem && documentRecord == nil)
                || (error.code == .permissionFailure && owner != nil) {
                zoneWentAway()
                return false
            }
            if error.code == .changeTokenExpired {
                tokens[zone] = nil
                fetchesAgain = true
                return true
            }
        }
        let what = zone == documentZone ? "a shared presentation" : "comments on a shared presentation"
        collaborationLog.error("Reading \(what, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        return true
    }

    /// The `Document` record with its snapshot: where a Mac joining starts from.
    private func loadDocument() async throws {
        let recordID = CKRecord.ID(recordName: CollaborationRecords.documentName, zoneID: documentZone)
        let record = try await database.record(for: recordID)
        documentRecord = record
        guard let info = CollaborationRecords.decode(SharedDocumentInfo.self, from: record[CollaborationRecords.infoKey] as? Data),
              let file = (record[CollaborationRecords.snapshotKey] as? CKAsset)?.fileURL,
              let snapshot = try? SyncSnapshot(encoded: Data(contentsOf: file)) else {
            throw CollaborationError.failed("The shared presentation hasn’t all come from iCloud yet.")
        }
        self.info = info
        if let share = try? await database.record(for: CloudKitCollaboration.shareID(in: documentZone)) as? CKShare { sharingChanged(share) }
        delegate?.channel(self, loaded: snapshot, info: info)
    }

    /// What a Mac reads of the `Document` and `Change` records in a document zone.
    private static let documentZoneKeys: [CKRecord.FieldKey] = [CollaborationRecords.infoKey, CollaborationRecords.revisionKey,
                                                                CollaborationRecords.changeIDKey, CollaborationRecords.authorKey, "authorName",
                                                                CollaborationRecords.changeKey, "changeFile"]

    private func fetchDocumentZone() async throws {
        var changes: [LoggedPresentationChange] = []
        var unread: [CKRecord.ID] = []
        var retitled: String?
        try await readZone(documentZone, desiredKeys: Self.documentZoneKeys) { record in
            if let share = record as? CKShare {
                sharingChanged(share)
            } else if record.recordType == CollaborationRecords.changeType {
                if let change = Self.loggedChange(from: record) { changes.append(change) } else { unread.append(record.recordID) }
            } else if record.recordType == CollaborationRecords.documentType {
                if let info = CollaborationRecords.decode(SharedDocumentInfo.self, from: record[CollaborationRecords.infoKey] as? Data) {
                    if let old = self.info, old.title != info.title { retitled = info.title }
                    self.info = info
                }
            }
        } failed: { id, error in
            if CollaborationRecords.revision(ofChange: id.recordName) != nil { unread.append(id) }
            collaborationLog.error("Reading \(id.recordName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        } deleted: { _ in }
        // A change that didn't come whole with the rest (a big one, whose file didn't come along) is read on its own; one
        // that still can't be is left for the Mac to find missing and ask for again.
        if !unread.isEmpty { changes += await readChanges(unread) }
        if !changes.isEmpty { delegate?.channel(self, received: changes) }
        if let retitled { delegate?.channel(self, retitled: retitled) }
    }

    /// Change records read by name, the way the snapshot is; any that can't be read are logged, saying why.
    private func readChanges(_ ids: [CKRecord.ID]) async -> [LoggedPresentationChange] {
        var found: [LoggedPresentationChange] = []
        do {
            let results = try await database.records(for: ids, desiredKeys: Self.documentZoneKeys)
            for id in ids {
                switch results[id] {
                case let .success(record)?:
                    if let change = Self.loggedChange(from: record) {
                        found.append(change)
                    } else {
                        collaborationLog.error("\(id.recordName, privacy: .public) can't be read: \(Self.describe(record), privacy: .public)")
                    }
                case let .failure(error)?:
                    collaborationLog.error("\(id.recordName, privacy: .public) can't be fetched: \(error.localizedDescription, privacy: .public)")
                case nil:
                    collaborationLog.error("\(id.recordName, privacy: .public) isn't in iCloud")
                }
            }
        } catch {
            collaborationLog.error("Reading changes by name failed: \(error.localizedDescription, privacy: .public)")
        }
        return found
    }

    /// What a change record holds, for the log when it can't be read.
    private static func describe(_ record: CKRecord) -> String {
        let inline = (record[CollaborationRecords.changeKey] as? Data).map { "\($0.count) bytes" } ?? "none"
        guard let asset = record["changeFile"] as? CKAsset else { return "inline \(inline), no file" }
        guard let url = asset.fileURL else { return "inline \(inline), file not downloaded" }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int).map { "\($0) bytes" } ?? "missing"
        return "inline \(inline), file \(size)"
    }

    func fetchChanges(_ revisions: ClosedRange<Int>) {
        guard isRunning else { return }
        let ids = revisions.prefix(400).map { CKRecord.ID(recordName: CollaborationRecords.changeName($0), zoneID: documentZone) }
        Task {
            let found = await readChanges(ids)
            if !found.isEmpty { delegate?.channel(self, received: found) }
            guard found.count < ids.count, isRunning else { return }
            // Some can't be had: the latest snapshot, if it's past them, is the way on.
            collaborationLog.error("Changes \(revisions.lowerBound)–\(revisions.upperBound) can't be read here; reading the latest snapshot")
            documentRecord = nil
            fetchSoon()
        }
    }

    private func fetchTalkZone() async throws {
        guard let talkZone else { return }
        var threads: [SharedComment] = []
        var gone: [UUID] = []
        var people: [Presence] = []
        try await readZone(talkZone, desiredKeys: nil) { record in
            if record.recordType == CollaborationRecords.commentType,
               let comment = CollaborationRecords.decode(SharedComment.self, from: record[CollaborationRecords.infoKey] as? Data) {
                comments[comment.thread.id] = record
                threads.append(comment)
            } else if record.recordType == CollaborationRecords.presenceType,
                      let info = CollaborationRecords.decode(PresenceInfo.self, from: record[CollaborationRecords.infoKey] as? Data) {
                let person = String(record.recordID.recordName.dropFirst("presence-".count))
                presence[person] = info
                people.append(Presence(person: person, info: info, date: record.modificationDate ?? Date()))
            }
        } failed: { id, error in
            collaborationLog.error("Reading \(id.recordName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        } deleted: { deletion in
            if deletion.recordType == CollaborationRecords.commentType, let id = UUID(uuidString: deletion.recordID.recordName) {
                comments[id] = nil
                gone.append(id)
            }
        }
        if !threads.isEmpty || !gone.isEmpty { delegate?.channel(self, receivedComments: threads, deleted: gone) }
        if !people.isEmpty { delegate?.channel(self, receivedPresence: people) }
    }

    private func readZone(_ zone: CKRecordZone.ID, desiredKeys: [CKRecord.FieldKey]?, _ changed: (CKRecord) -> Void,
                          failed: (CKRecord.ID, Error) -> Void, deleted: (CKDatabase.RecordZoneChange.Deletion) -> Void) async throws {
        var token = tokens[zone]
        while true {
            let result = try await database.recordZoneChanges(inZoneWith: zone, since: token, desiredKeys: desiredKeys)
            for (id, outcome) in result.modificationResultsByID {
                switch outcome {
                case let .success(modification): changed(modification.record)
                case let .failure(error): failed(id, error)
                }
            }
            result.deletions.forEach(deleted)
            token = result.changeToken
            tokens[zone] = token
            if !result.moreComing { break }
        }
    }

    nonisolated static func loggedChange(from record: CKRecord) -> LoggedPresentationChange? {
        guard let revision = (record[CollaborationRecords.revisionKey] as? Int) ?? CollaborationRecords.revision(ofChange: record.recordID.recordName),
              let id = record[CollaborationRecords.changeIDKey] as? String else { return nil }
        var data = record[CollaborationRecords.changeKey] as? Data
        if data == nil, let file = (record["changeFile"] as? CKAsset)?.fileURL { data = try? Data(contentsOf: file) }
        guard let data, let change = try? PresentationChange(encoded: data) else { return nil }
        return LoggedPresentationChange(revision: revision, id: id, author: record[CollaborationRecords.authorKey] as? String ?? "",
                            authorName: record["authorName"] as? String ?? "", change: change)
    }

    // MARK: Writing

    func claim(_ change: LoggedPresentationChange, completion: @escaping (ClaimResult) -> Void) {
        let record = CKRecord(recordType: CollaborationRecords.changeType,
                              recordID: CKRecord.ID(recordName: CollaborationRecords.changeName(change.revision), zoneID: documentZone))
        record[CollaborationRecords.revisionKey] = change.revision
        record[CollaborationRecords.changeIDKey] = change.id
        record[CollaborationRecords.authorKey] = change.author
        record["authorName"] = change.authorName
        let data = change.change.encoded
        var file: URL?
        if data.count > 600_000 {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("change-\(change.id)")
            try? data.write(to: url)
            file = url
            record["changeFile"] = CKAsset(fileURL: url)
            collaborationLog.notice("Sending change \(change.revision) as a file of \(data.count) bytes")
        } else {
            record[CollaborationRecords.changeKey] = data
        }
        let database = database
        Task {
            defer { if let file { try? FileManager.default.removeItem(at: file) } }
            do {
                // A record of that name, made already, means another change took the revision first.
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
                _ = try result.saveResults[record.recordID]?.get()
                completion(.claimed)
            } catch {
                var result = Self.claimResult(error, recordID: record.recordID)
                if case .failed = result, Self.wasTaken(error, recordID: record.recordID),
                   let existing = await readChanges([record.recordID]).first {
                    // A big change took the revision first: its file doesn't come with the answer, so it's read whole.
                    result = .taken(existing)
                }
                if case .failed = result {
                    collaborationLog.error("Sending change \(change.revision) failed: \(error.localizedDescription, privacy: .public)")
                }
                completion(result)
            }
        }
    }

    /// Whether saving a change failed because a change of that revision is in the log already.
    private static func wasTaken(_ error: Error, recordID: CKRecord.ID) -> Bool {
        guard var error = error as? CKError else { return false }
        if error.code == .partialFailure, let inner = error.partialErrorsByItemID?[recordID] as? CKError { error = inner }
        return error.code == .serverRecordChanged
    }

    private static func claimResult(_ error: Error, recordID: CKRecord.ID) -> ClaimResult {
        guard var error = error as? CKError else { return .failed(error) }
        if error.code == .partialFailure, let inner = error.partialErrorsByItemID?[recordID] as? CKError { error = inner }
        switch error.code {
        case .serverRecordChanged:
            if let server = error.serverRecord, let existing = loggedChange(from: server) { return .taken(existing) }
            return .failed(error)
        case .permissionFailure:
            return .notAllowed
        default:
            return .failed(error)
        }
    }

    func saveSnapshot(_ snapshot: SyncSnapshot, title: String) {
        let database = database
        let zone = documentZone
        Task {
            for _ in 0..<3 {
                do {
                    let record: CKRecord
                    if let documentRecord {
                        record = documentRecord
                    } else {
                        record = try await database.record(for: CKRecord.ID(recordName: CollaborationRecords.documentName, zoneID: zone))
                    }
                    var info = CollaborationRecords.decode(SharedDocumentInfo.self, from: record[CollaborationRecords.infoKey] as? Data)
                        ?? SharedDocumentInfo(title: title, ownerName: "")
                    guard info.snapshotRevision < snapshot.revision else { return }
                    info.snapshotRevision = snapshot.revision
                    if owner == nil { info.title = title }
                    let updated = try CloudKitCollaboration.documentRecord(info: info, snapshot: snapshot, in: zone, existing: record)
                    let result = try await database.modifyRecords(saving: [updated], deleting: [], savePolicy: .ifServerRecordUnchanged)
                    documentRecord = try result.saveResults[updated.recordID]?.get()
                    self.info = info
                    await collectGarbage(below: snapshot.revision - 2_000)
                    return
                } catch let error as CKError where error.code == .serverRecordChanged {
                    documentRecord = error.serverRecord
                } catch {
                    collaborationLog.error("Saving a snapshot failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
        }
    }

    func setTitle(_ title: String) {
        let database = database
        let zone = documentZone
        let id = id
        Task {
            for _ in 0..<3 {
                do {
                    let record: CKRecord
                    if let documentRecord {
                        record = documentRecord
                    } else {
                        record = try await database.record(for: CKRecord.ID(recordName: CollaborationRecords.documentName, zoneID: zone))
                    }
                    guard var info = CollaborationRecords.decode(SharedDocumentInfo.self, from: record[CollaborationRecords.infoKey] as? Data),
                          info.title != title else { return }
                    info.title = title
                    record[CollaborationRecords.infoKey] = CollaborationRecords.encode(info)
                    let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
                    documentRecord = try result.saveResults[record.recordID]?.get()
                    self.info = info
                    // The name the system's invitations show, too.
                    await service.retitleShare(of: id, to: title)
                    return
                } catch let error as CKError where error.code == .serverRecordChanged {
                    documentRecord = error.serverRecord
                } catch {
                    collaborationLog.error("Renaming a shared document failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
        }
    }

    /// Changes long since in a snapshot go, a few hundred at a time; plenty are kept for comments made against older
    /// revisions and for Macs catching up.
    private func collectGarbage(below revision: Int) async {
        guard revision > lastGarbageRevision else { return }
        let from = lastGarbageRevision + 1
        let to = min(revision, from + 399)
        let ids = (from...to).map { CKRecord.ID(recordName: CollaborationRecords.changeName($0), zoneID: documentZone) }
        _ = try? await database.modifyRecords(saving: [], deleting: ids, atomically: false)
        lastGarbageRevision = to
    }

    /// The talk zone, joining it first if this person hasn't yet.
    private func joinedTalkZone() async -> CKRecordZone.ID? {
        if talkZone == nil, let url = info?.talkURL { talkZone = try? await service.joinTalk(url) }
        return talkZone
    }

    func save(_ comment: SharedComment, base: CommentThread?, completion: @escaping (Result<SharedComment, Error>) -> Void) {
        let database = database
        Task {
            guard let talkZone = await joinedTalkZone() else {
                completion(.failure(CollaborationError.failed("Comments can’t be reached yet.")))
                return
            }
            var comment = comment
            for _ in 0..<3 {
                let record = CloudKitCollaboration.commentRecord(comment, in: talkZone, existing: comments[comment.thread.id])
                do {
                    let result = try await service.retrying {
                        try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
                    }
                    if let saved = try result.saveResults[record.recordID]?.get() { comments[comment.thread.id] = saved }
                    completion(.success(comment))
                    return
                } catch let error as CKError where error.code == .serverRecordChanged {
                    // Someone changed the thread meanwhile: both changes, merged, go again.
                    guard let server = error.serverRecord,
                          let theirs = CollaborationRecords.decode(SharedComment.self, from: server[CollaborationRecords.infoKey] as? Data) else { break }
                    comments[comment.thread.id] = server
                    comment = SharedComment(thread: SharedComment.merge(local: comment.thread, base: base, server: theirs.thread),
                                            slideID: theirs.slideID)
                } catch {
                    collaborationLog.error("Saving a comment failed: \(error.localizedDescription, privacy: .public)")
                    completion(.failure(CloudKitCollaboration.problem(error)))
                    return
                }
            }
            completion(.failure(CollaborationError.failed("The comment couldn’t be saved. Try again in a little while.")))
        }
    }

    func deleteComment(_ id: UUID) {
        comments[id] = nil
        let database = database
        Task {
            guard let talkZone = await joinedTalkZone() else { return }
            _ = try? await database.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: id.uuidString, zoneID: talkZone)])
        }
    }

    func setPresence(viewing: Bool, isOwner: Bool, permission: CollaboratorPermission) {
        guard let me = service.status.me else { return }
        let database = database
        Task {
            guard let talkZone = await joinedTalkZone() else { return }
            let record = CKRecord(recordType: CollaborationRecords.presenceType,
                                  recordID: CKRecord.ID(recordName: CollaborationRecords.presenceName(me.id), zoneID: talkZone))
            record[CollaborationRecords.infoKey] = CollaborationRecords.encode(PresenceInfo(name: me.name, isViewing: viewing, inboxURL: service.inboxURL,
                                                                                           isOwner: isOwner, permission: permission))
            _ = try? await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        }
    }

    func sendNotice(title: String, body: String, to people: [String]) {
        let owner = owner ?? service.status.me?.id ?? CKCurrentUserDefaultName
        let inboxes = people.compactMap { presence[$0]?.inboxURL }
        Task {
            for inbox in Set(inboxes) { await service.deliver(title: title, body: body, document: id, owner: owner, to: inbox) }
        }
    }
}
