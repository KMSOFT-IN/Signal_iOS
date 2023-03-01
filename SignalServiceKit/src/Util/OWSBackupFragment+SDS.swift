//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

// NOTE: This file is generated by /Scripts/sds_codegen/sds_generate.py.
// Do not manually edit it, instead run `sds_codegen.sh`.

// MARK: - Record

public struct BackupFragmentRecord: SDSRecord {
    public weak var delegate: SDSRecordDelegate?

    public var tableMetadata: SDSTableMetadata {
        OWSBackupFragmentSerializer.table
    }

    public static var databaseTableName: String {
        OWSBackupFragmentSerializer.table.tableName
    }

    public var id: Int64?

    // This defines all of the columns used in the table
    // where this model (and any subclasses) are persisted.
    public let recordType: SDSRecordType
    public let uniqueId: String

    // Properties
    public let attachmentId: String?
    public let downloadFilePath: String?
    public let encryptionKey: Data
    public let recordName: String
    public let relativeFilePath: String?
    public let uncompressedDataLength: UInt64?

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case attachmentId
        case downloadFilePath
        case encryptionKey
        case recordName
        case relativeFilePath
        case uncompressedDataLength
    }

    public static func columnName(_ column: BackupFragmentRecord.CodingKeys, fullyQualified: Bool = false) -> String {
        fullyQualified ? "\(databaseTableName).\(column.rawValue)" : column.rawValue
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return
        }
        delegate.updateRowId(rowID)
    }
}

// MARK: - Row Initializer

public extension BackupFragmentRecord {
    static var databaseSelection: [SQLSelectable] {
        CodingKeys.allCases
    }

    init(row: Row) {
        id = row[0]
        recordType = row[1]
        uniqueId = row[2]
        attachmentId = row[3]
        downloadFilePath = row[4]
        encryptionKey = row[5]
        recordName = row[6]
        relativeFilePath = row[7]
        uncompressedDataLength = row[8]
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(backupFragmentColumn column: BackupFragmentRecord.CodingKeys) {
        appendLiteral(BackupFragmentRecord.columnName(column))
    }
    mutating func appendInterpolation(backupFragmentColumnFullyQualified column: BackupFragmentRecord.CodingKeys) {
        appendLiteral(BackupFragmentRecord.columnName(column, fullyQualified: true))
    }
}

// MARK: - Deserialization

// TODO: Rework metadata to not include, for example, columns, column indices.
extension OWSBackupFragment {
    // This method defines how to deserialize a model, given a
    // database row.  The recordType column is used to determine
    // the corresponding model class.
    class func fromRecord(_ record: BackupFragmentRecord) throws -> OWSBackupFragment {

        guard let recordId = record.id else {
            throw SDSError.invalidValue
        }

        switch record.recordType {
        case .backupFragment:

            let uniqueId: String = record.uniqueId
            let attachmentId: String? = record.attachmentId
            let downloadFilePath: String? = record.downloadFilePath
            let encryptionKey: Data = record.encryptionKey
            let recordName: String = record.recordName
            let relativeFilePath: String? = record.relativeFilePath
            let uncompressedDataLength: NSNumber? = SDSDeserialization.optionalNumericAsNSNumber(record.uncompressedDataLength, name: "uncompressedDataLength", conversion: { NSNumber(value: $0) })

            return OWSBackupFragment(grdbId: recordId,
                                     uniqueId: uniqueId,
                                     attachmentId: attachmentId,
                                     downloadFilePath: downloadFilePath,
                                     encryptionKey: encryptionKey,
                                     recordName: recordName,
                                     relativeFilePath: relativeFilePath,
                                     uncompressedDataLength: uncompressedDataLength)

        default:
            owsFailDebug("Unexpected record type: \(record.recordType)")
            throw SDSError.invalidValue
        }
    }
}

// MARK: - SDSModel

extension OWSBackupFragment: SDSModel {
    public var serializer: SDSSerializer {
        // Any subclass can be cast to it's superclass,
        // so the order of this switch statement matters.
        // We need to do a "depth first" search by type.
        switch self {
        default:
            return OWSBackupFragmentSerializer(model: self)
        }
    }

    public func asRecord() throws -> SDSRecord {
        try serializer.asRecord()
    }

    public var sdsTableName: String {
        BackupFragmentRecord.databaseTableName
    }

    public static var table: SDSTableMetadata {
        OWSBackupFragmentSerializer.table
    }

    public class func anyEnumerateIndexable(
        transaction: SDSAnyReadTransaction,
        block: @escaping (SDSIndexableModel) -> Void
    ) {
        anyEnumerate(transaction: transaction, batched: false) { model, _ in
            block(model)
        }
    }
}

// MARK: - DeepCopyable

extension OWSBackupFragment: DeepCopyable {

    public func deepCopy() throws -> AnyObject {
        // Any subclass can be cast to it's superclass,
        // so the order of this switch statement matters.
        // We need to do a "depth first" search by type.
        guard let id = self.grdbId?.int64Value else {
            throw OWSAssertionError("Model missing grdbId.")
        }

        do {
            let modelToCopy = self
            assert(type(of: modelToCopy) == OWSBackupFragment.self)
            let uniqueId: String = modelToCopy.uniqueId
            let attachmentId: String? = modelToCopy.attachmentId
            let downloadFilePath: String? = modelToCopy.downloadFilePath
            let encryptionKey: Data = modelToCopy.encryptionKey
            let recordName: String = modelToCopy.recordName
            let relativeFilePath: String? = modelToCopy.relativeFilePath
            let uncompressedDataLength: NSNumber? = modelToCopy.uncompressedDataLength

            return OWSBackupFragment(grdbId: id,
                                     uniqueId: uniqueId,
                                     attachmentId: attachmentId,
                                     downloadFilePath: downloadFilePath,
                                     encryptionKey: encryptionKey,
                                     recordName: recordName,
                                     relativeFilePath: relativeFilePath,
                                     uncompressedDataLength: uncompressedDataLength)
        }

    }
}

// MARK: - Table Metadata

extension OWSBackupFragmentSerializer {

    // This defines all of the columns used in the table
    // where this model (and any subclasses) are persisted.
    static var idColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "id", columnType: .primaryKey) }
    static var recordTypeColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "recordType", columnType: .int64) }
    static var uniqueIdColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "uniqueId", columnType: .unicodeString, isUnique: true) }
    // Properties
    static var attachmentIdColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "attachmentId", columnType: .unicodeString, isOptional: true) }
    static var downloadFilePathColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "downloadFilePath", columnType: .unicodeString, isOptional: true) }
    static var encryptionKeyColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "encryptionKey", columnType: .blob) }
    static var recordNameColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "recordName", columnType: .unicodeString) }
    static var relativeFilePathColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "relativeFilePath", columnType: .unicodeString, isOptional: true) }
    static var uncompressedDataLengthColumn: SDSColumnMetadata { SDSColumnMetadata(columnName: "uncompressedDataLength", columnType: .int64, isOptional: true) }

    // TODO: We should decide on a naming convention for
    //       tables that store models.
    public static var table: SDSTableMetadata {
        SDSTableMetadata(collection: OWSBackupFragment.collection(),
                         tableName: "model_OWSBackupFragment",
                         columns: [
        idColumn,
        recordTypeColumn,
        uniqueIdColumn,
        attachmentIdColumn,
        downloadFilePathColumn,
        encryptionKeyColumn,
        recordNameColumn,
        relativeFilePathColumn,
        uncompressedDataLengthColumn
        ])
    }
}

// MARK: - Save/Remove/Update

@objc
public extension OWSBackupFragment {
    func anyInsert(transaction: SDSAnyWriteTransaction) {
        sdsSave(saveMode: .insert, transaction: transaction)
    }

    // Avoid this method whenever feasible.
    //
    // If the record has previously been saved, this method does an overwriting
    // update of the corresponding row, otherwise if it's a new record, this
    // method inserts a new row.
    //
    // For performance, when possible, you should explicitly specify whether
    // you are inserting or updating rather than calling this method.
    func anyUpsert(transaction: SDSAnyWriteTransaction) {
        let isInserting: Bool
        if OWSBackupFragment.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil {
            isInserting = false
        } else {
            isInserting = true
        }
        sdsSave(saveMode: isInserting ? .insert : .update, transaction: transaction)
    }

    // This method is used by "updateWith..." methods.
    //
    // This model may be updated from many threads. We don't want to save
    // our local copy (this instance) since it may be out of date.  We also
    // want to avoid re-saving a model that has been deleted.  Therefore, we
    // use "updateWith..." methods to:
    //
    // a) Update a property of this instance.
    // b) If a copy of this model exists in the database, load an up-to-date copy,
    //    and update and save that copy.
    // b) If a copy of this model _DOES NOT_ exist in the database, do _NOT_ save
    //    this local instance.
    //
    // After "updateWith...":
    //
    // a) Any copy of this model in the database will have been updated.
    // b) The local property on this instance will always have been updated.
    // c) Other properties on this instance may be out of date.
    //
    // All mutable properties of this class have been made read-only to
    // prevent accidentally modifying them directly.
    //
    // This isn't a perfect arrangement, but in practice this will prevent
    // data loss and will resolve all known issues.
    func anyUpdate(transaction: SDSAnyWriteTransaction, block: (OWSBackupFragment) -> Void) {

        block(self)

        guard let dbCopy = type(of: self).anyFetch(uniqueId: uniqueId,
                                                   transaction: transaction) else {
            return
        }

        // Don't apply the block twice to the same instance.
        // It's at least unnecessary and actually wrong for some blocks.
        // e.g. `block: { $0 in $0.someField++ }`
        if dbCopy !== self {
            block(dbCopy)
        }

        dbCopy.sdsSave(saveMode: .update, transaction: transaction)
    }

    // This method is an alternative to `anyUpdate(transaction:block:)` methods.
    //
    // We should generally use `anyUpdate` to ensure we're not unintentionally
    // clobbering other columns in the database when another concurrent update
    // has occurred.
    //
    // There are cases when this doesn't make sense, e.g. when  we know we've
    // just loaded the model in the same transaction. In those cases it is
    // safe and faster to do a "overwriting" update
    func anyOverwritingUpdate(transaction: SDSAnyWriteTransaction) {
        sdsSave(saveMode: .update, transaction: transaction)
    }

    func anyRemove(transaction: SDSAnyWriteTransaction) {
        sdsRemove(transaction: transaction)
    }

    func anyReload(transaction: SDSAnyReadTransaction) {
        anyReload(transaction: transaction, ignoreMissing: false)
    }

    func anyReload(transaction: SDSAnyReadTransaction, ignoreMissing: Bool) {
        guard let latestVersion = type(of: self).anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            if !ignoreMissing {
                owsFailDebug("`latest` was unexpectedly nil")
            }
            return
        }

        setValuesForKeys(latestVersion.dictionaryValue)
    }
}

// MARK: - OWSBackupFragmentCursor

@objc
public class OWSBackupFragmentCursor: NSObject, SDSCursor {
    private let transaction: GRDBReadTransaction
    private let cursor: RecordCursor<BackupFragmentRecord>?

    init(transaction: GRDBReadTransaction, cursor: RecordCursor<BackupFragmentRecord>?) {
        self.transaction = transaction
        self.cursor = cursor
    }

    public func next() throws -> OWSBackupFragment? {
        guard let cursor = cursor else {
            return nil
        }
        guard let record = try cursor.next() else {
            return nil
        }
        return try OWSBackupFragment.fromRecord(record)
    }

    public func all() throws -> [OWSBackupFragment] {
        var result = [OWSBackupFragment]()
        while true {
            guard let model = try next() else {
                break
            }
            result.append(model)
        }
        return result
    }
}

// MARK: - Obj-C Fetch

// TODO: We may eventually want to define some combination of:
//
// * fetchCursor, fetchOne, fetchAll, etc. (ala GRDB)
// * Optional "where clause" parameters for filtering.
// * Async flavors with completions.
//
// TODO: I've defined flavors that take a read transaction.
//       Or we might take a "connection" if we end up having that class.
@objc
public extension OWSBackupFragment {
    class func grdbFetchCursor(transaction: GRDBReadTransaction) -> OWSBackupFragmentCursor {
        let database = transaction.database
        do {
            let cursor = try BackupFragmentRecord.fetchCursor(database)
            return OWSBackupFragmentCursor(transaction: transaction, cursor: cursor)
        } catch {
            owsFailDebug("Read failed: \(error)")
            return OWSBackupFragmentCursor(transaction: transaction, cursor: nil)
        }
    }

    // Fetches a single model by "unique id".
    class func anyFetch(uniqueId: String,
                        transaction: SDSAnyReadTransaction) -> OWSBackupFragment? {
        assert(!uniqueId.isEmpty)

        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            let sql = "SELECT * FROM \(BackupFragmentRecord.databaseTableName) WHERE \(backupFragmentColumn: .uniqueId) = ?"
            return grdbFetchOne(sql: sql, arguments: [uniqueId], transaction: grdbTransaction)
        }
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    class func anyEnumerate(transaction: SDSAnyReadTransaction,
                            block: @escaping (OWSBackupFragment, UnsafeMutablePointer<ObjCBool>) -> Void) {
        anyEnumerate(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    class func anyEnumerate(transaction: SDSAnyReadTransaction,
                            batched: Bool = false,
                            block: @escaping (OWSBackupFragment, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerate(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    class func anyEnumerate(transaction: SDSAnyReadTransaction,
                            batchSize: UInt,
                            block: @escaping (OWSBackupFragment, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            let cursor = OWSBackupFragment.grdbFetchCursor(transaction: grdbTransaction)
            Batching.loop(batchSize: batchSize,
                          loopBlock: { stop in
                                do {
                                    guard let value = try cursor.next() else {
                                        stop.pointee = true
                                        return
                                    }
                                    block(value, stop)
                                } catch let error {
                                    owsFailDebug("Couldn't fetch model: \(error)")
                                }
                              })
        }
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    class func anyEnumerateUniqueIds(transaction: SDSAnyReadTransaction,
                                     block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        anyEnumerateUniqueIds(transaction: transaction, batched: false, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    class func anyEnumerateUniqueIds(transaction: SDSAnyReadTransaction,
                                     batched: Bool = false,
                                     block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerateUniqueIds(transaction: transaction, batchSize: batchSize, block: block)
    }

    // Traverses all records' unique ids.
    // Records are not visited in any particular order.
    //
    // If batchSize > 0, the enumeration is performed in autoreleased batches.
    class func anyEnumerateUniqueIds(transaction: SDSAnyReadTransaction,
                                     batchSize: UInt,
                                     block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            grdbEnumerateUniqueIds(transaction: grdbTransaction,
                                   sql: """
                    SELECT \(backupFragmentColumn: .uniqueId)
                    FROM \(BackupFragmentRecord.databaseTableName)
                """,
                batchSize: batchSize,
                block: block)
        }
    }

    // Does not order the results.
    class func anyFetchAll(transaction: SDSAnyReadTransaction) -> [OWSBackupFragment] {
        var result = [OWSBackupFragment]()
        anyEnumerate(transaction: transaction) { (model, _) in
            result.append(model)
        }
        return result
    }

    // Does not order the results.
    class func anyAllUniqueIds(transaction: SDSAnyReadTransaction) -> [String] {
        var result = [String]()
        anyEnumerateUniqueIds(transaction: transaction) { (uniqueId, _) in
            result.append(uniqueId)
        }
        return result
    }

    class func anyCount(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            return BackupFragmentRecord.ows_fetchCount(grdbTransaction.database)
        }
    }

    // WARNING: Do not use this method for any models which do cleanup
    //          in their anyWillRemove(), anyDidRemove() methods.
    class func anyRemoveAllWithoutInstantation(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbTransaction):
            do {
                try BackupFragmentRecord.deleteAll(grdbTransaction.database)
            } catch {
                owsFailDebug("deleteAll() failed: \(error)")
            }
        }

        if ftsIndexMode != .never {
            FullTextSearchFinder.allModelsWereRemoved(collection: collection(), transaction: transaction)
        }
    }

    class func anyRemoveAllWithInstantation(transaction: SDSAnyWriteTransaction) {
        // To avoid mutationDuringEnumerationException, we need
        // to remove the instances outside the enumeration.
        let uniqueIds = anyAllUniqueIds(transaction: transaction)

        var index: Int = 0
        Batching.loop(batchSize: Batching.kDefaultBatchSize,
                      loopBlock: { stop in
            guard index < uniqueIds.count else {
                stop.pointee = true
                return
            }
            let uniqueId = uniqueIds[index]
            index += 1
            guard let instance = anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                owsFailDebug("Missing instance.")
                return
            }
            instance.anyRemove(transaction: transaction)
        })

        if ftsIndexMode != .never {
            FullTextSearchFinder.allModelsWereRemoved(collection: collection(), transaction: transaction)
        }
    }

    class func anyExists(
        uniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        assert(!uniqueId.isEmpty)

        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            let sql = "SELECT EXISTS ( SELECT 1 FROM \(BackupFragmentRecord.databaseTableName) WHERE \(backupFragmentColumn: .uniqueId) = ? )"
            let arguments: StatementArguments = [uniqueId]
            return try! Bool.fetchOne(grdbTransaction.database, sql: sql, arguments: arguments) ?? false
        }
    }
}

// MARK: - Swift Fetch

public extension OWSBackupFragment {
    class func grdbFetchCursor(sql: String,
                               arguments: StatementArguments = StatementArguments(),
                               transaction: GRDBReadTransaction) -> OWSBackupFragmentCursor {
        do {
            let sqlRequest = SQLRequest<Void>(sql: sql, arguments: arguments, cached: true)
            let cursor = try BackupFragmentRecord.fetchCursor(transaction.database, sqlRequest)
            return OWSBackupFragmentCursor(transaction: transaction, cursor: cursor)
        } catch {
            Logger.verbose("sql: \(sql)")
            owsFailDebug("Read failed: \(error)")
            return OWSBackupFragmentCursor(transaction: transaction, cursor: nil)
        }
    }

    class func grdbFetchOne(sql: String,
                            arguments: StatementArguments = StatementArguments(),
                            transaction: GRDBReadTransaction) -> OWSBackupFragment? {
        assert(!sql.isEmpty)

        do {
            let sqlRequest = SQLRequest<Void>(sql: sql, arguments: arguments, cached: true)
            guard let record = try BackupFragmentRecord.fetchOne(transaction.database, sqlRequest) else {
                return nil
            }

            return try OWSBackupFragment.fromRecord(record)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }
}

// MARK: - SDSSerializer

// The SDSSerializer protocol specifies how to insert and update the
// row that corresponds to this model.
class OWSBackupFragmentSerializer: SDSSerializer {

    private let model: OWSBackupFragment
    public required init(model: OWSBackupFragment) {
        self.model = model
    }

    // MARK: - Record

    func asRecord() throws -> SDSRecord {
        let id: Int64? = model.grdbId?.int64Value

        let recordType: SDSRecordType = .backupFragment
        let uniqueId: String = model.uniqueId

        // Properties
        let attachmentId: String? = model.attachmentId
        let downloadFilePath: String? = model.downloadFilePath
        let encryptionKey: Data = model.encryptionKey
        let recordName: String = model.recordName
        let relativeFilePath: String? = model.relativeFilePath
        let uncompressedDataLength: UInt64? = archiveOptionalNSNumber(model.uncompressedDataLength, conversion: { $0.uint64Value })

        return BackupFragmentRecord(delegate: model, id: id, recordType: recordType, uniqueId: uniqueId, attachmentId: attachmentId, downloadFilePath: downloadFilePath, encryptionKey: encryptionKey, recordName: recordName, relativeFilePath: relativeFilePath, uncompressedDataLength: uncompressedDataLength)
    }
}

// MARK: - Deep Copy

#if TESTABLE_BUILD
@objc
public extension OWSBackupFragment {
    // We're not using this method at the moment,
    // but we might use it for validation of
    // other deep copy methods.
    func deepCopyUsingRecord() throws -> OWSBackupFragment {
        guard let record = try asRecord() as? BackupFragmentRecord else {
            throw OWSAssertionError("Could not convert to record.")
        }
        return try OWSBackupFragment.fromRecord(record)
    }
}
#endif