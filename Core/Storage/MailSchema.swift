import Foundation
import SwiftData

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
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let location = url ?? URL.applicationSupportDirectory
                .appending(path: "Dispatch", directoryHint: .isDirectory).appending(path: "mail.sqlite")
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: location, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: MailMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        return container
    }
}
