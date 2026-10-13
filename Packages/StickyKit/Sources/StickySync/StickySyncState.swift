import CloudKit
import Foundation
import StickyDomain

struct StickySyncState: Codable, Sendable {
    var engine: CKSyncEngine.State.Serialization?
    var records: [String: Record] = [:]
    var accountID: String?
    var deferredRecords: [String: Record] = [:]
    var deferredDeletions: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case engine, records, accountID, deferredRecords, deferredDeletions
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        engine = try values.decodeIfPresent(CKSyncEngine.State.Serialization.self, forKey: .engine)
        records = try values.decodeIfPresent([String: Record].self, forKey: .records) ?? [:]
        accountID = try values.decodeIfPresent(String.self, forKey: .accountID)
        deferredRecords = try values.decodeIfPresent([String: Record].self, forKey: .deferredRecords) ?? [:]
        deferredDeletions = try values.decodeIfPresent(Set<String>.self, forKey: .deferredDeletions) ?? []
    }

    struct Record: Codable, Sendable {
        var systemFields: Data
        var note: Sticky
    }
}
