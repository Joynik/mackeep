import Foundation

/// The engines of the storage of Mackeep.
enum StorageEngine: String, CaseIterable, Identifiable, Codable {
    /// No storage is selected on a fresh installation.
    case unconfigured

    /// The Dropbox folder of the home directory.
    case dropbox

    /// The Google Drive folder.
    case googleDrive = "google_drive"

    /// The iCloud folder.
    case iCloud = "icloud"

    /// A folder of the home directory.
    case fileSystem = "file_system"

    var id: String { rawValue }

    /// The title of the engine.
    var title: String {
        switch self {
        case .unconfigured:
            return L10n.string("settings.storage.unconfigured")
        case .dropbox:
            return L10n.string("settings.storage.dropbox")
        case .googleDrive:
            return L10n.string("settings.storage.googleDrive")
        case .iCloud:
            return L10n.string("settings.storage.iCloud")
        case .fileSystem:
            return L10n.string("settings.storage.fileSystem")
        }
    }

    /// The standard folder of the engine, when it has one.
    var standardPath: String? {
        let home: URL = URL(fileURLWithPath: NSHomeDirectory())
        switch self {
        case .dropbox:
            return home.appendingPathComponent("Dropbox").path
        case .googleDrive:
            return home.appendingPathComponent("Library/CloudStorage").path
        case .iCloud:
            return home.appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs"
            ).path
        case .fileSystem, .unconfigured:
            return nil
        }
    }

    /// Whether the storage of the engine is available on this Mac.
    var isAvailable: Bool {
        switch self {
        case .fileSystem:
            return true
        case .googleDrive:
            // The folder of Google Drive has a suffix that changes
            guard let path: String = standardPath else { return false }
            let contents: [String] = (try? FileManager.default.contentsOfDirectory(
                atPath: path
            )) ?? []
            return contents.contains { $0.hasPrefix("GoogleDrive") }
        default:
            guard let path: String = standardPath else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: path,
                isDirectory: &isDirectory
            )
        }
    }
}
