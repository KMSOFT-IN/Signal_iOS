//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// A bucket for SQLite utilities.
public enum SqliteUtil {
    /// Determine whether a table, column, or view name *could* lead to SQL injection.
    ///
    /// In some cases, you'd like to write something like this:
    ///
    ///     // This causes an error:
    ///     let sql = "SELECT * FROM ?"
    ///     try Row.fetchAll(db, sql: sql, arguments: [myTableName])
    ///
    /// Unfortunately, GRDB (perhaps because of SQLite) doesn't allow this kind of thing. That means
    /// we have to use string interpolation, which can be dangerous due to SQL injection. This helps
    /// keep that safe.
    ///
    /// Instead, you'd write something like this:
    ///
    ///     owsAssert(SqliteUtil.isSafe(myTableName))
    ///     let sql = "SELECT * FROM \(myTableName)"
    ///     try Row.fetchAll(db, sql: sql)
    ///
    /// This is unlikely to happen for our app, and should always return `true`.
    ///
    /// This check may return false negatives. For example, SQLite supports empty table names which
    /// this function would mark unsafe.
    ///
    /// - Parameter sqlName: The table, column, or view name to be checked.
    /// - Returns: Whether the name is safe to use in SQL string interpolation.
    public static func isSafe(sqlName: String) -> Bool {
        !sqlName.isEmpty &&
        sqlName.utf8.count < 1000 &&
        !sqlName.lowercased().starts(with: "sqlite") &&
        sqlName.range(of: "^[a-zA-Z][a-zA-Z0-9_]*$", options: .regularExpression) != nil
    }

    /// A bucket for FTS5 utilities.
    public enum Fts5 {
        public enum IntegrityCheckResult {
            case ok
            case corrupted
        }

        /// Run an [integrity-check command] on an FTS5 table.
        ///
        /// - Parameter db: A database connection.
        /// - Parameter ftsTableName: The virtual FTS5 table to use. This table name must be "safe"
        ///   according to ``Sqlite.isSafe``. If it's not, a fatal error will be thrown.
        /// - Parameter rank: The `rank` parameter to use. See the SQLite docs for more information.
        /// - Returns: An integrity check result.
        ///
        /// [integrity-check command]: https://www.sqlite.org/fts5.html#the_integrity_check_command
        public static func integrityCheck(
            db: Database,
            ftsTableName: String,
            compareToExternalContentTable: Bool
        ) throws -> IntegrityCheckResult {
            owsAssert(SqliteUtil.isSafe(sqlName: ftsTableName))

            let sql: String
            if compareToExternalContentTable {
                sql = "INSERT INTO \(ftsTableName) (\(ftsTableName), rank) VALUES ('integrity-check', 1)"
            } else {
                sql = "INSERT INTO \(ftsTableName) (\(ftsTableName)) VALUES ('integrity-check')"
            }

            do {
                try db.execute(sql: sql)
            } catch {
                if
                    let dbError = error as? DatabaseError,
                    dbError.extendedResultCode == .SQLITE_CORRUPT_VTAB
                {
                    return .corrupted
                } else {
                    throw error
                }
            }

            return .ok
        }

        /// Run a [rebuild command] on an FTS5 table.
        ///
        /// - Parameter db: A database connection.
        /// - Parameter ftsTableName: The virtual FTS5 table to use. This table name must be "safe"
        ///   according to ``Sqlite.isSafe``. If it's not, a fatal error will be thrown.
        ///
        /// [rebuild command]: https://www.sqlite.org/fts5.html#the_rebuild_command
        public static func rebuild(db: Database, ftsTableName: String) throws {
            owsAssert(SqliteUtil.isSafe(sqlName: ftsTableName))

            try db.execute(
                sql: "INSERT INTO \(ftsTableName) (\(ftsTableName)) VALUES ('rebuild')"
            )
        }
    }
}
