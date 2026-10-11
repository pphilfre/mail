import Foundation
import SwiftData
import UIKit

enum MailSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [MailAccount.self, MailMessage.self, MailThread.self, MailAttachment.self, MailFolder.self,
         OutgoingMessage.self, PendingMailOperation.self, StoreMetadata.self]
    }
}

enum MailMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MailSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor
enum MailStorage {
    static func open(at url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MailSchemaV1.self)
        let configuration: ModelConfiguration
        let backgroundRefresh = UserDefaults.standard.bool(forKey: "backgroundMailRefresh")
        let protection = LocalMailProtection.storageProtection(backgroundRefresh: backgroundRefresh)
        let canConfigureProtection = UIApplication.shared.isProtectedDataAvailable
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let location = url ?? URL.applicationSupportDirectory
                .appending(path: "Dispatch", directoryHint: .isDirectory).appending(path: "mail.sqlite")
            // Protect existing stores and external blobs before opening, and newly created
            // SQLite/WAL/SHM files after opening. Directories pass protection to new files.
            if canConfigureProtection {
                try LocalMailProtection.protectTree(location.deletingLastPathComponent(), protection: protection, preservingDraftAttachments: true)
            }
            configuration = ModelConfiguration(schema: schema, url: location, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: MailMigrationPlan.self, configurations: [configuration])
        if !inMemory && canConfigureProtection {
            try LocalMailProtection.protectTree(configuration.url.deletingLastPathComponent(), protection: protection, preservingDraftAttachments: true)
        }
        container.mainContext.autosaveEnabled = false
        return container
    }
}
