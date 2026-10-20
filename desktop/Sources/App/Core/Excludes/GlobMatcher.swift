import Foundation

/// A matcher of the exclusion patterns, the way Mackeep matches them.
///
/// The patterns follow the `.gitignore` semantics: `*` matches anything but a
/// slash, `?` matches a single character and `**` matches anything, slashes
/// included. A pattern without a slash matches a name at any depth.
struct GlobMatcher {
    /// The patterns of the matcher.
    private let patterns: [Pattern]

    /// A pattern of the matcher.
    private struct Pattern {
        /// The regular expression of the pattern.
        let expression: NSRegularExpression

        /// Whether the pattern is relative to the root.
        let isAnchored: Bool
    }

    /// Create a matcher.
    ///
    /// - Parameter patterns: The patterns.
    init(patterns: [String]) {
        self.patterns = patterns.compactMap { GlobMatcher.pattern(for: $0) }
    }

    /// Whether the patterns are empty.
    var isEmpty: Bool { patterns.isEmpty }

    /// Whether a path is matched by one of the patterns.
    ///
    /// - Parameter path: The path, relative to the root.
    /// - Returns: True when the path is matched.
    func matches(_ path: String) -> Bool {
        let components: [String] = path.split(separator: "/").map(String.init)
        for pattern: Pattern in patterns {
            if pattern.isAnchored {
                if pattern.expression.firstMatch(
                    in: path,
                    range: NSRange(path.startIndex..., in: path)
                ) != nil {
                    return true
                }
            } else {
                for component: String in components {
                    if pattern.expression.firstMatch(
                        in: component,
                        range: NSRange(component.startIndex..., in: component)
                    ) != nil {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// The files of a folder that are matched by the patterns.
    ///
    /// - Parameter url: The path of the folder.
    /// - Returns: The paths of the files, relative to the folder.
    func matchingFiles(in url: URL) -> [String] {
        guard !isEmpty else { return [] }
        let manager: FileManager = .default
        guard let enumerator: FileManager.DirectoryEnumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return []
        }

        // The paths of the files are compared to the resolved path of the
        // folder, /var is a link to /private/var on macOS.
        let root: String = url.resolvingSymlinksInPath().path

        var files: [String] = []
        for case let file as URL in enumerator {
            var isDirectory: ObjCBool = false
            let path: String = file.resolvingSymlinksInPath().path
            guard
                manager.fileExists(atPath: path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                continue
            }
            let relative: String = path.replacingOccurrences(
                of: root + "/",
                with: ""
            )
            if matches(relative) { files.append(relative) }
        }
        return files
    }

    /// Build the pattern of a mask.
    ///
    /// - Parameter mask: The mask.
    /// - Returns: The pattern, nil when the mask is empty.
    private static func pattern(for mask: String) -> Pattern? {
        var source: String = mask
        var isAnchored: Bool = false

        if source.hasPrefix("!") {
            source.removeFirst()
        }
        if source.hasSuffix("/") {
            source.removeLast()
        }
        if source.contains("/") {
            isAnchored = true
        }
        while source.hasPrefix("/") {
            source.removeFirst()
            isAnchored = true
        }
        guard !source.isEmpty else { return nil }

        let expression: String = GlobMatcher.expression(for: source, anchored: isAnchored)
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: expression
        ) else {
            return nil
        }
        return Pattern(expression: regex, isAnchored: isAnchored)
    }

    /// Build the regular expression of a mask.
    ///
    /// - Parameters:
    ///   - mask: The mask.
    ///   - anchored: Whether the mask is relative to the root.
    /// - Returns: The regular expression.
    private static func expression(for mask: String, anchored: Bool) -> String {
        var result: String = ""
        var index: String.Index = mask.startIndex

        while index < mask.endIndex {
            let character: Character = mask[index]
            if character == "*" {
                let nextIndex: String.Index = mask.index(after: index)
                let next: Character? = nextIndex < mask.endIndex ? mask[nextIndex] : nil
                if next == "*" {
                    // "**/" matches any number of folders, including none
                    let afterStars: String.Index = mask.index(after: nextIndex)
                    if afterStars < mask.endIndex, mask[afterStars] == "/" {
                        result += "(?:.*/)?"
                        index = mask.index(after: afterStars)
                        continue
                    }
                    result += ".*"
                    index = nextIndex
                    continue
                }
                result += "[^/]*"
            } else if character == "?" {
                result += "[^/]"
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = mask.index(after: index)
        }

        let prefix: String = anchored ? "^" : "^"
        let suffix: String = anchored ? "$" : "$"
        return prefix + result + suffix
    }
}
