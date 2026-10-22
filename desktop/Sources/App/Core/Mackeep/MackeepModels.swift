import Foundation

/// The models of the JSON answers of Mackeep.
///
/// The field names are the ones of the JSON, the coding keys are given for
/// each of them. The fields that may be missing are optional, so an older
/// version of Mackeep can be read.
enum MackeepSchema {
    /// The version of the schema of the answers.
    static let version: Int = 4
}

/// The storage of Mackeep.
struct MackeepStorage: Codable, Equatable, Sendable {
    /// The engine of the storage.
    let engine: String

    /// The path of the storage.
    let path: String

    /// The name of the directory of the backup inside the storage.
    let directory: String

    /// The full path of the backup directory.
    let resolvedBackupDir: String

    /// Whether the backup directory exists.
    let exists: Bool

    enum CodingKeys: String, CodingKey {
        case engine
        case path
        case directory
        case resolvedBackupDir = "resolved_backup_dir"
        case exists
    }
}

/// The configuration of Mackeep.
struct MackeepConfig: Codable, Equatable, Sendable {
    /// The version of the schema.
    let schemaVersion: Int

    /// The version of Mackeep.
    let version: String

    /// The path of the config file.
    let configFile: String

    /// The main directory where the custom application configs are read.
    let customAppsDir: String?

    /// The directories where the custom application configs are read.
    let customAppsDirs: [String]

    /// The storage of Mackeep.
    let storage: MackeepStorage

    /// The applications to sync.
    let appsToSync: [String]

    /// The applications to ignore.
    let appsToIgnore: [String]

    /// The global exclusion rules.
    let globalExclude: [String]

    /// The global exclusion rules of the XDG directory.
    let globalXdgExclude: [String]?

    /// The problems of the config file of Mackeep.
    ///
    /// The broken rules are skipped, they do not stop Mackeep from working.
    let errors: [String]?

    /// Missing on older CLI versions, which do not support this setting.
    var allowExternalPaths: Bool? = nil
    var storageConfigured: Bool? = nil
    var supportsSafeCancellation: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case allowExternalPaths = "allow_external_paths"
        case storageConfigured = "storage_configured"
        case supportsSafeCancellation = "supports_safe_cancellation"
        case schemaVersion = "schema_version"
        case version
        case configFile = "config_file"
        case customAppsDir = "custom_apps_dir"
        case customAppsDirs = "custom_apps_dirs"
        case storage
        case appsToSync = "apps_to_sync"
        case appsToIgnore = "apps_to_ignore"
        case globalExclude = "global_exclude"
        case globalXdgExclude = "global_xdg_exclude"
        case errors
    }
}

/// A path of an application.
struct MackeepPath: Codable, Equatable, Identifiable {
    /// The path, relative to the home directory.
    let path: String

    /// Whether the path exists.
    let exists: Bool

    /// Whether the path is a directory.
    let isDir: Bool

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path
        case exists
        case isDir = "is_dir"
    }
}

/// The source of an application.
enum MackeepAppSource: String, Codable, Equatable {
    /// An application of the database of Mackeep.
    case builtin

    /// An application of the user.
    case custom
}

/// An application of Mackeep.
struct MackeepApplication: Codable, Equatable, Identifiable, Sendable {
    /// The version of the schema.
    let schemaVersion: Int

    /// The identifier of the application.
    let name: String

    /// The name of the application, for the user.
    let displayName: String

    /// Where the application comes from.
    let source: MackeepAppSource

    /// The path of the config file of the application.
    let cfgPath: String

    /// The paths of the application.
    let files: [MackeepPath]

    /// The XDG paths of the application.
    let xdgFiles: [MackeepPath]

    /// The exclusion rules of the application.
    let exclude: [String]?

    /// The XDG exclusion rules of the application.
    let xdgExclude: [String]?

    /// The reason why the config file of the application is not fully used.
    ///
    /// The broken rules are skipped, the application is still used.
    let error: String?

    var id: String { name }

    /// Whether the application comes from the user.
    var isCustom: Bool { source == .custom }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case name
        case displayName = "display_name"
        case source
        case cfgPath = "cfg_path"
        case files
        case xdgFiles = "xdg_files"
        case exclude
        case xdgExclude = "xdg_exclude"
        case error
    }
}

/// The reason why a path is excluded.
struct MackeepExclusionReason: Codable, Equatable, Sendable {
    /// The pattern that excluded the path.
    let pattern: String

    /// The section the pattern comes from.
    let section: String

    /// The config file the pattern comes from.
    let file: String
}

/// An operation of a plan.
struct MackeepAction: Codable, Equatable, Identifiable, Sendable {
    /// The application of the operation.
    let app: String

    /// The kind of the operation: copy, skip_excluded, skip_missing,
    /// conflict or stale_in_backup.
    let action: String

    /// The source of the operation.
    let src: String

    /// The destination of the operation.
    let dst: String

    /// The size of the file.
    let sizeBytes: Int?

    /// The reason why the path is excluded.
    let reason: MackeepExclusionReason?

    /// Whether the file would be overwritten.
    let wouldOverwrite: Bool?

    /// Schema 4 explicitly marks stale paths that will be deleted.
    var willRemove: Bool? = nil

    var id: String { "\(app)|\(action)|\(src)" }

    enum CodingKeys: String, CodingKey {
        case app
        case action
        case src
        case dst
        case sizeBytes = "size_bytes"
        case reason
        case wouldOverwrite = "would_overwrite"
        case willRemove = "will_remove"
    }
}

/// The summary of a plan.
struct MackeepSummary: Codable, Equatable, Sendable {
    /// The applications of the plan.
    let apps: [String]

    /// The number of operations of each kind.
    let actions: [String: Int]

    /// The number of operations.
    let totalActions: Int

    /// The total size of the files.
    let totalBytes: Int

    /// The number of files.
    let files: Int?

    /// Whether the plan was truncated.
    let truncated: Bool?

    /// The maximum number of operations.
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case apps
        case actions
        case totalActions = "total_actions"
        case totalBytes = "total_bytes"
        case files
        case truncated
        case limit
    }
}

/// The plan of a dry-run.
struct MackeepPlan: Codable, Equatable, Sendable {
    /// The version of the schema.
    let schemaVersion: Int

    /// The operations of the plan.
    let actions: [MackeepAction]

    /// The summary of the plan.
    let summary: MackeepSummary

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case actions
        case summary
    }
}

/// An event of a running command.
struct MackeepEvent: Codable, Equatable, Sendable {
    /// The version of the schema.
    let schemaVersion: Int

    /// The kind of the event: start, file, done or error.
    let event: String

    /// The application of the event.
    let app: String?

    /// The operation of the event.
    let action: String?

    /// The source of the operation.
    let src: String?

    /// The destination of the operation.
    let dst: String?

    /// The size of the file.
    let sizeBytes: Int?

    /// The reason why the path is excluded.
    let reason: MackeepExclusionReason?

    /// The number of files of a done event.
    let files: Int?

    /// The number of bytes of a done event.
    let bytes: Int?

    /// The number of skipped files of a done event.
    let skipped: Int?

    /// The message of an error event.
    let message: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
        case app
        case action
        case src
        case dst
        case sizeBytes = "size_bytes"
        case reason
        case files
        case bytes
        case skipped
        case message
    }
}

/// The error of a command.
struct MackeepError: Codable, Equatable, Sendable {
    /// The code of the error.
    let code: String

    /// The message of the error.
    let message: String
}
