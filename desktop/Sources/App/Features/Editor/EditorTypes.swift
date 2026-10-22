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
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let root: URL = isXDG ? EditorPath.xdgDirectory : EditorPath.homeDirectory
        return root.appendingPathComponent(path)
    }

    /// Make a path relative to the home directory, or to the XDG config home.
    ///
    /// - Parameters:
    ///   - url: The absolute path.
    ///   - isXDG: Whether the path is an XDG one.
    /// - Returns: The relative path, the absolute one when it is outside.
    static func relativePath(of url: URL, isXDG: Bool) -> String {
        let root: URL = isXDG ? EditorPath.xdgDirectory : EditorPath.homeDirectory

        let rootPath: String = root.standardizedFileURL.path
        let path: String = url.standardizedFileURL.path
        let prefix: String = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }

    /// The home directory of the user.
    static var homeDirectory: URL {
        if isTesting {
            let path =
                Self.testValue("MACKEEP_TEST_HOME")
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    "MackeepTests-\(ProcessInfo.processInfo.processIdentifier)"
                ).path
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    static var isTesting: Bool {
        Bundle.main.bundleIdentifier == "com.joynik.mackeep.testing"
            || ProcessInfo.processInfo.environment["MACKEEP_TESTING"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// LaunchServices can discard environment overrides; test builds also accept arguments.
    static func testValue(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key] { return value }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + key), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    /// The XDG config home of the user.
    static var xdgDirectory: URL {
        let home: URL = EditorPath.homeDirectory
        return URL(
            fileURLWithPath: isTesting
                ? home.appendingPathComponent(".config").path
                : ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
                    ?? home.appendingPathComponent(".config").path)
    }

    /// Cut the parts of a path that the tool does not accept.
    ///
    /// The tool only accepts relative paths, so the variables of the shell
    /// and the root of the section are taken off, the leading slash is taken
    /// off as well, so the path is always relative.
    ///
    /// - Parameters:
    ///   - text: The path or the mask, as it is written.
    ///   - isXDG: Whether it belongs to the XDG section.
    /// - Returns: The relative path.
    static func corrected(_ text: String, isXDG: Bool, allowExternalPaths: Bool = false) -> String {
        let trimmed: String = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }

        let expanded: String = EditorPath.expanded(trimmed)

        // The path is inside the root of the section.
        let rootPath: String = (isXDG
            ? EditorPath.xdgDirectory
            : EditorPath.homeDirectory
        ).standardizedFileURL.path
        let prefix: String = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if expanded.hasPrefix(prefix) {
            return String(expanded.dropFirst(prefix.count))
        }

        if allowExternalPaths, expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        // The path is outside of the root, the leading slash is cut.
        var relative: String = String(expanded.drop(while: { $0 == "/" }))
        if isXDG, let xdg: String = EditorPath.xdgRelativePath,
           relative.hasPrefix(xdg + "/")
        {
            // The XDG config home is inside the home directory, it is cut
            // as well.
            relative = String(relative.dropFirst(xdg.count + 1))
        }
        return relative
    }

    /// Replace the variables of a path by the directories they stand for.
    ///
    /// The tilde is the home directory, "$HOME" is the home directory too and
    /// "$XDG_CONFIG_HOME" is the XDG config home.
    ///
    /// - Parameter path: The path, as it is written.
    /// - Returns: The path with the absolute directories.
    static func expanded(_ path: String) -> String {
        let text: String = path

        // The tilde is the home directory.
        if text == "~" {
            return EditorPath.homeDirectory.path
        } else if text.hasPrefix("~/") {
            return EditorPath.homeDirectory.path
                + "/" + String(text.dropFirst(2))
        }

        // The variables of the shell.
        let variables: [(name: String, directory: URL)] = [
            ("$XDG_CONFIG_HOME", EditorPath.xdgDirectory),
            ("${XDG_CONFIG_HOME}", EditorPath.xdgDirectory),
            ("$HOME", EditorPath.homeDirectory),
            ("${HOME}", EditorPath.homeDirectory),
        ]
        for variable: (name: String, directory: URL) in variables {
            if text == variable.name {
                return variable.directory.path
            } else if text.hasPrefix(variable.name + "/") {
                return variable.directory.path
                    + "/" + String(text.dropFirst(variable.name.count + 1))
            }
        }
        return text
    }

    /// The XDG config home, relative to the home directory.
    ///
    /// It is nil when the XDG config home is not inside the home directory.
    static var xdgRelativePath: String? {
        let root: String = EditorPath.xdgDirectory.standardizedFileURL.path
        let home: String = EditorPath.homeDirectory.standardizedFileURL.path
        let prefix: String = home.hasSuffix("/") ? home : home + "/"
        guard root.hasPrefix(prefix) else { return nil }
        return String(root.dropFirst(prefix.count))
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
