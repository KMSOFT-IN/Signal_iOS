//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

@objc
extension MockSSKEnvironment {
    public func configureGrdb() {
        do {
            try GRDBSchemaMigrator.migrateDatabase(
                databaseStorage: databaseStorage,
                isMainDatabase: true,
                runDataMigrations: true
            )
        } catch {
            owsFail("\(error)")
        }
    }

    /// Set up a mock SSK environment as well as ``DependenciesBridge``.
    public static func activate() {
        let sskEnvironment = MockSSKEnvironment()
        MockSSKEnvironment.setShared(sskEnvironment)

        DependenciesBridge.setupSingleton(
            databaseStorage: sskEnvironment.databaseStorage,
            tsAccountManager: sskEnvironment.tsAccountManager,
            signalService: sskEnvironment.signalService,
            storageServiceManager: sskEnvironment.storageServiceManager,
            syncManager: sskEnvironment.syncManager,
            ows2FAManager: sskEnvironment.ows2FAManager
        )

        sskEnvironment.configureGrdb()
        sskEnvironment.warmCaches()
    }
}

#endif
