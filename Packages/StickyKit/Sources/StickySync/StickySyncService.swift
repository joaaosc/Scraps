import CloudKit
import CryptoKit
import Foundation
import OSLog
import StickyDomain
import StickyStorage

/// One engine per app process. The local store remains the source for edits;
/// CloudKit stores persistent notes in the signed-in person's private zone.
actor StickySyncService: CKSyncEngineDelegate {
    private let store: FileStickyStore
    private let beforeImport: @Sendable () async -> Bool
    private let report: @Sendable (StickySyncStatus) async -> Void
    private let stateURL: URL
    private var persisted: StickySyncState
    private var engine: CKSyncEngine?
    private var changes: Task<Void, Never>?
    private var enabled = false
    private var failure: String?
    private var assetFiles: [String: Set<URL>] = [:]
    private var manualSync: Task<Void, Never>?
    private let zoneID = CKRecordZone.ID(zoneName: "Scraps")
    private static let recordType = "Scrap"
    private static let logger = Logger(subsystem: StickyKitIdentity.bundleIdentifier, category: "Sync")

    init(
        store: FileStickyStore,
        beforeImport: @escaping @Sendable () async -> Bool,
        report: @escaping @Sendable (StickySyncStatus) async -> Void
    ) {
        self.store = store
        self.beforeImport = beforeImport
        self.report = report
        self.stateURL = store.directoryURL.deletingLastPathComponent().appending(path: "Sync/state.json")
        self.persisted = (try? JSONDecoder().decode(StickySyncState.self, from: Data(contentsOf: stateURL))) ?? StickySyncState()
    }

    func start(acceptAccountChange: Bool = false) async {
        guard engine == nil else { return }
        enabled = true
        failure = nil
        let container = CKContainer(identifier: StickyKitIdentity.cloudContainerIdentifier)
        do {
            let accountStatus = try await container.accountStatus()
            guard enabled, !Task.isCancelled else { return }
            guard accountStatus == .available else {
                await report(.notSignedIn)
                // The engine still observes a later sign-in and resumes.
                initializeEngine(container)
                observeLocalChanges()
                return
            }
            let account = try await container.userRecordID().recordName
            guard enabled, !Task.isCancelled else { return }
            if let previous = persisted.accountID, previous != account {
                if acceptAccountChange { persisted = StickySyncState() }
                else {
                    enabled = false
                    await report(.accountChanged)
                    return
                }
            }
            persisted.accountID = account
            initializeEngine(container)
            observeLocalChanges()
            try await queueLocalChanges()
            persistState()
            await synchronize()
        } catch { await reportFailure(error) }
    }

    func stop() async {
        enabled = false
        manualSync?.cancel()
        changes?.cancel(); changes = nil
        let old = engine
        engine = nil
        await old?.cancelOperations()
        persistState()
    }

    func synchronize() async {
        if let manualSync { await manualSync.value; return }
        let task = Task { await performSynchronization() }
        manualSync = task
        defer { manualSync = nil }
        await task.value
    }

    private func performSynchronization() async {
        guard enabled, let engine else { return }
        failure = nil
        await report(.syncing)
        do {
            guard await beforeImport() else {
                await reportFailure(CocoaError(.fileWriteUnknown))
                return
            }
            try await retryDeferredImports()
            try await queueLocalChanges()
            try await engine.sendChanges()
            guard enabled, self.engine === engine, !Task.isCancelled else { return }
            try await engine.fetchChanges()
            guard enabled, self.engine === engine, !Task.isCancelled else { return }
            try await queueLocalChanges()
            try await engine.sendChanges()
            guard enabled, self.engine === engine, !Task.isCancelled else { return }
            if let failure { await report(.failed(failure)) }
            else { await report(.upToDate) }
        } catch { await reportFailure(error) }
    }

    private func initializeEngine(_ container: CKContainer) {
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: persisted.engine,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
    }

    private func observeLocalChanges() {
        let stream = StickyChanges.stream()
        changes = Task { [weak self] in
            for await _ in stream {
                guard !Task.isCancelled else { return }
                do { try await self?.queueLocalChanges() }
                catch { await self?.reportFailure(error) }
            }
        }
    }

    private func queueLocalChanges() async throws {
        guard enabled, let engine else { return }
        let notes = try await store.synchronizationSnapshot()
        let present = try await store.existingIdentifiers().union(notes.map(\.id))
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for note in notes {
            if let synced = persisted.records[note.id.uuidString]?.note,
               StickySyncMerge.equivalent(note, synced) { continue }
            pending.append(.saveRecord(recordID(note.id)))
        }
        for key in persisted.records.keys {
            guard let id = UUID(uuidString: key), !present.contains(id) else { continue }
            pending.append(.deleteRecord(recordID(id)))
        }
        if !pending.isEmpty {
            engine.state.add(pendingRecordZoneChanges: pending)
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard enabled, engine === syncEngine else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            await self?.record(for: id)
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        switch event {
        case let .stateUpdate(update):
            persisted.engine = update.stateSerialization
            persistState()
        case let .accountChange(change):
            switch change.changeType {
            case let .signIn(currentUser):
                if let previous = persisted.accountID, previous != currentUser.recordName {
                    pauseForAccountChange(syncEngine)
                    await report(.accountChanged)
                } else {
                    persisted.accountID = currentUser.recordName
                    do { try await queueLocalChanges() } catch { await reportFailure(error) }
                }
            case .signOut, .switchAccounts:
                pauseForAccountChange(syncEngine)
                await report(.accountChanged)
            @unknown default: break
            }
            persistState()
        case let .fetchedRecordZoneChanges(changes):
            guard enabled else { return }
            let canImport = await beforeImport()
            for change in changes.modifications {
                do {
                    persisted.deferredRecords[change.record.recordID.recordName] = try recordInfo(change.record)
                    if canImport { try await importRecord(change.record) }
                } catch { await reportFailure(error) }
            }
            for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                persisted.deferredDeletions.insert(deletion.recordID.recordName)
                if canImport {
                    do { try await importDeletion(deletion.recordID) }
                    catch { await reportFailure(error) }
                }
            }
            if !canImport { await reportFailure(CocoaError(.fileWriteUnknown)) }
            persistState()
        case let .sentDatabaseChanges(changes):
            for failed in changes.failedZoneSaves { await reportFailure(failed.error) }
        case let .didFetchRecordZoneChanges(change):
            if let error = change.error { await reportFailure(error) }
        case let .sentRecordZoneChanges(changes):
            for record in changes.savedRecords {
                do { try remember(record); removeUploadedAssets(record.recordID.recordName) } catch { await reportFailure(error) }
            }
            for id in changes.deletedRecordIDs { persisted.records[id.recordName] = nil; removeUploadedAssets(id.recordName) }
            for failed in changes.failedRecordSaves {
                switch failed.error.code {
                case .serverRecordChanged:
                    if let server = failed.error.serverRecord {
                        do {
                            try await importRecord(server)
                            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
                        } catch { await reportFailure(error) }
                    } else { await reportFailure(failed.error) }
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failed.record.recordID)])
                case .unknownItem:
                    persisted.records[failed.record.recordID.recordName] = nil
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failed.record.recordID)])
                default: await reportFailure(failed.error)
                }
            }
            for (_, error) in changes.failedRecordDeletes where error.code != .unknownItem {
                await reportFailure(error)
            }
            persistState()
            do { try await queueLocalChanges() } catch { await reportFailure(error) }
        case .willFetchChanges, .willSendChanges:
            if enabled { await report(.syncing) }
        case .didFetchChanges, .didSendChanges:
            if enabled, failure == nil, syncEngine.state.pendingRecordZoneChanges.isEmpty { await report(.upToDate) }
        default: break
        }
    }

    private func pauseForAccountChange(_ engine: CKSyncEngine) {
        enabled = false
        changes?.cancel(); changes = nil
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
        engine.state.remove(pendingDatabaseChanges: engine.state.pendingDatabaseChanges)
        // Cancellation runs after this serial event completes, avoiding a
        // delegate deadlock. Local notes are never removed on account changes.
        Task { await engine.cancelOperations() }
        self.engine = nil
        persisted = StickySyncState()
    }

    private func record(for id: CKRecord.ID) async -> CKRecord? {
        do {
            guard enabled, id.zoneID == zoneID,
                  let noteID = UUID(uuidString: id.recordName),
                  let note = try await store.synchronizationSnapshot().first(where: { $0.id == noteID }) else { return nil }
            let record: CKRecord
            if let fields = persisted.records[id.recordName]?.systemFields {
                let coder = try NSKeyedUnarchiver(forReadingFrom: fields)
                coder.requiresSecureCoding = true
                record = CKRecord(coder: coder) ?? CKRecord(recordType: Self.recordType, recordID: id)
                coder.finishDecoding()
            } else { record = CKRecord(recordType: Self.recordType, recordID: id) }
            let data = try payload(StickySyncMerge.cloudCopy(note))
            record["schema"] = 1 as NSNumber
            if data.count < 900_000 {
                record.encryptedValues["payload"] = data as NSData
                record["document"] = nil
            } else {
                let file = stateURL.deletingLastPathComponent().appending(path: "Assets/\(UUID().uuidString).json")
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                assetFiles[id.recordName, default: []].insert(file)
                record["document"] = CKAsset(fileURL: file)
                record.encryptedValues["payload"] = nil
            }
            return record
        } catch { await reportFailure(error); return nil }
    }

    private func importRecord(_ record: CKRecord) async throws {
        guard record.recordID.zoneID == zoneID, record.recordType == Self.recordType else { return }
        let remote = try note(from: record)
        guard record.recordID.recordName == remote.id.uuidString else { throw CocoaError(.coderReadCorrupt) }
        let local = try await store.synchronizationSnapshot().first { $0.id == remote.id }
        let ancestor = persisted.records[record.recordID.recordName]?.note
        let resolution = StickySyncMerge.resolve(
            local: local, remote: remote, ancestor: ancestor,
            conflictID: conflictIdentifier(local: local, remote: remote)
        )
        if let recovered = resolution.recoveredEdit {
            let existing = try await store.synchronizationSnapshot().first { $0.id == recovered.id }
            if existing == nil { try await store.applySynchronized(recovered, replacing: nil) }
        }
        if resolution.note != local { try await store.applySynchronized(resolution.note, replacing: local) }
        try remember(record)
        if !StickySyncMerge.equivalent(resolution.note, remote) {
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        }
        if let recovered = resolution.recoveredEdit {
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(recovered.id))])
        }
    }

    private func importDeletion(_ id: CKRecord.ID) async throws {
        guard let uuid = UUID(uuidString: id.recordName) else { return }
        if let local = try await store.synchronizationSnapshot().first(where: { $0.id == uuid }) {
            if let ancestor = persisted.records[id.recordName]?.note,
               !StickySyncMerge.equivalent(local, ancestor), local.deletedAt == nil {
                var recovered = local.duplicated()
                recovered.conflictSourceID = local.id
                try await store.applySynchronized(recovered, replacing: nil)
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(recovered.id))])
            }
            try await store.deleteSynchronized(id: uuid, replacing: local)
        }
        persisted.records[id.recordName] = nil
        persisted.deferredDeletions.remove(id.recordName)
    }

    private func remember(_ record: CKRecord) throws {
        persisted.records[record.recordID.recordName] = try recordInfo(record)
        persisted.deferredRecords[record.recordID.recordName] = nil
    }

    private func recordInfo(_ record: CKRecord) throws -> StickySyncState.Record {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return .init(systemFields: coder.encodedData, note: try note(from: record))
    }

    private func retryDeferredImports() async throws {
        for (name, saved) in persisted.deferredRecords {
            let coder = try NSKeyedUnarchiver(forReadingFrom: saved.systemFields)
            coder.requiresSecureCoding = true
            guard let record = CKRecord(coder: coder) else { throw CocoaError(.coderReadCorrupt) }
            coder.finishDecoding()
            record.encryptedValues["payload"] = try payload(saved.note) as NSData
            try await importRecord(record)
            persisted.deferredRecords[name] = nil
        }
        for name in persisted.deferredDeletions {
            try await importDeletion(CKRecord.ID(recordName: name, zoneID: zoneID))
        }
        persistState()
    }

    private func note(from record: CKRecord) throws -> Sticky {
        let data: Data
        if let inline = record.encryptedValues["payload"] as? Data { data = inline }
        else if let file = (record["document"] as? CKAsset)?.fileURL { data = try Data(contentsOf: file) }
        else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(Sticky.self, from: data)
    }

    private func payload(_ note: Sticky) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(note)
    }

    private func conflictIdentifier(local: Sticky?, remote: Sticky) -> UUID {
        let pieces = [local, remote].compactMap { $0 }.compactMap { try? payload(StickySyncMerge.cloudCopy($0)) }
            .sorted { $0.lexicographicallyPrecedes($1) }
        let hash = Array(SHA256.hash(data: pieces.reduce(into: Data()) { $0.append($1) }).prefix(16))
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7], hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
    }

    private func removeUploadedAssets(_ recordName: String) {
        let files = assetFiles.removeValue(forKey: recordName) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    private func recordID(_ id: UUID) -> CKRecord.ID { CKRecord.ID(recordName: id.uuidString, zoneID: zoneID) }

    private func persistState() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(persisted).write(to: stateURL, options: .atomic)
        } catch {
            failure = error.localizedDescription
            Self.logger.error("Could not persist sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reportFailure(_ error: any Error) async {
        guard enabled else { return }
        if let cloud = error as? CKError, cloud.code == .notAuthenticated {
            await report(.notSignedIn)
        } else {
            let message = error.localizedDescription
            failure = message
            await report(.failed(message))
        }
    }
}
