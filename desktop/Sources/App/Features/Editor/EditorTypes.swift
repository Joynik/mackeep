import Foundation

/// A path of an application, as it is edited.
struct EditorPath: Identifiable, Equatable {
    /// The path, relative to the home directory.
    var path: String

    /// Whether the path is an XDG one.
    var isXDG: Bool = false

    /// The absolute path of the file or of the folder.
    var url: URL {
        EditorPath.absoluteURL(of: path, isXDG: isXDG)
    }

    var id: String { "\(isXDG ? "xdg:" : "home:")\(path)" }

    /// Whether the path exists.
    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The absolute path of a path of an application.
    ///
    /// - Parameters:
    ///   - path: The path, relative to the home directory.
    ///   - isXDG: Whether the path is an XDG one.
    /// - Returns: The absolute path.
    static func absoluteURL(of path: String, isXDG: Bool) -> URL {
        let home: URL = URL(fileURLWithPath: NSHomeDirectory())
        if isXDG {
            let xdg: URL = URL(fileURLWithPath: ProcessInfo.processInfo
                .environment["XDG_CONFIG_HOME"] ?? home.appendingPathComponent(".config").path)
            return xdg.appendingPathComponent(path)
        }
        return home.appendingPathComponent(path)
    }

    /// Make a path relative to the home directory, or to the XDG config home.
    ///
    /// - Parameters:
    ///   - url: The absolute path.
    ///   - isXDG: Whether the path is an XDG one.
    /// - Returns: The relative path, the absolute one when it is outside.
    static func relativePath(of url: URL, isXDG: Bool) -> String {
        let home: URL = URL(fileURLWithPath: NSHomeDirectory())
        let root: URL = isXDG
            ? URL(fileURLWithPath: ProcessInfo.processInfo
                .environment["XDG_CONFIG_HOME"] ?? home.appendingPathComponent(".config").path)
            : home

        let rootPath: String = root.standardizedFileURL.path
        let path: String = url.standardizedFileURL.path
        let prefix: String = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }
}

/// The sections of a config file of an application.
enum EditorSection: String, CaseIterable, Identifiable {
    /// The name of the application.
    case application

    /// The paths of the application.
    case configurationFiles = "configuration_files"

    /// The XDG paths of the application.
    case xdgConfigurationFiles = "xdg_configuration_files"

    /// The exclusion rules.
    case exclude

    /// The XDG exclusion rules.
    case xdgExclude = "xdg_exclude"

    var id: String { rawValue }

    /// The title of the section.
    var title: String {
        switch self {
        case .application: L10n.string("editor.section.application")
        case .configurationFiles: L10n.string("editor.section.configurationFiles")
        case .xdgConfigurationFiles: L10n.string("editor.section.xdgConfigurationFiles")
        case .exclude: L10n.string("editor.section.exclude")
        case .xdgExclude: L10n.string("editor.section.xdgExclude")
        }
    }

    /// Whether the section holds paths.
    var holdsPaths: Bool {
        self == .configurationFiles || self == .xdgConfigurationFiles
    }

    /// Whether the section holds exclusion rules.
    var holdsExclusions: Bool {
        self == .exclude || self == .xdgExclude
    }
}

/// The templates of a new application.
enum ApplicationTemplate: String, CaseIterable, Identifiable {
    /// An empty application.
    case empty

    /// An application with a single config file.
    case singleFile

    /// An application with a folder and exclusions.
    case folder

    /// An application that uses the XDG directory.
    case xdg

    /// An application that uses a plist of the preferences.
    case preferences

    var id: String { rawValue }

    /// The title of the template.
    var title: String {
        switch self {
        case .empty: L10n.string("template.empty")
        case .singleFile: L10n.string("template.singleFile")
        case .folder: L10n.string("template.folder")
        case .xdg: L10n.string("template.xdg")
        case .preferences: L10n.string("template.preferences")
        }
    }

    /// The sections of the template.
    var sections: [EditorSection] {
        switch self {
        case .empty: [.application]
        case .singleFile: [.application, .configurationFiles]
        case .folder: [.application, .configurationFiles, .exclude]
        case .xdg: [.application, .xdgConfigurationFiles, .xdgExclude]
        case .preferences: [.application, .configurationFiles]
        }
    }
}
