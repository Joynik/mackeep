import Foundation

/// A matcher of the exclusion patterns, the way Mackeep matches them.
///
/// The patterns follow the `.gitignore` semantics: `*` matches anything but a
/// slash, `?` matches a single character and `**` matches anything, slashes
/// included. A pattern without a slash matches a name at any depth.
struct GlobMatcher: Sendable {
    /// The patterns of the matcher.
    private let patterns: [Pattern]

    /// A pattern of the matcher.
    private struct Pattern: Sendable {
        /// The regular expression of the pattern.
        let expression: NSRegularExpression

        /// Whether the pattern is relative to the root.
        let isAnchored: Bool
        let raw: String
        let negated: Bool
        let directoryOnly: Bool
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
    func matches(_ path: String, isDirectory: Bool = false) -> Bool {
        reason(for: path, isDirectory: isDirectory) != nil
    }

    /// Report the last matching rule, respecting excluded parent directories.
    func reason(for path: String, isDirectory: Bool = false) -> String? {
        let components = path.split(separator: "/").filter { $0 != "." }.map(String.init)
        for index in components.indices {
            let prefix = components[...index].joined(separator: "/")
            let directory = index < components.count - 1 || isDirectory
            let deciding = patterns.reversed().first { pattern in
                if pattern.isAnchored {
                    return (!pattern.directoryOnly || directory)
                        && pattern.expression.matches(prefix)
                }
                return components[...index].enumerated().contains { offset, name in
                    (!pattern.directoryOnly || offset < index || directory)
                        && pattern.expression.matches(name)
                }
            }
            if let deciding, !deciding.negated { return deciding.raw }
        }
        return nil
    }

    /// The files of a folder that are matched by the patterns.
    ///
    /// The paths are relative to the root of the tree, the way the tool
    /// matches the patterns.
    ///
    /// - Parameters:
    ///   - url: The path of the folder.
    ///   - root: The root of the tree, the folder itself when it is not
    ///     given.
    /// - Returns: The paths of the files, relative to the root.
    func matchingFiles(in url: URL, relativeTo root: URL? = nil, limit: Int = 300) -> [String] {
        guard !isEmpty else { return [] }
        let manager: FileManager = .default
        guard let enumerator: FileManager.DirectoryEnumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return []
        }

        // Match logical paths, including symlink leaves, relative to the same root.
        let base = (root ?? url).standardizedFileURL.path

        var files: [String] = []
        for case let file as URL in enumerator {
            if Task.isCancelled || files.count >= limit { break }
            var isDirectory: ObjCBool = false
            let path: String = file.standardizedFileURL.path
            guard
                manager.fileExists(atPath: path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                continue
            }
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            if matches(relative) { files.append(relative) }
        }
        return files
    }

    /// Build the pattern of a mask.
    ///
    /// - Parameter mask: The mask.
    /// - Returns: The pattern, nil when the mask is empty.
    private static func pattern(for mask: String) -> Pattern? {
        var source = mask.trimmingCharacters(in: .whitespaces)
        guard !source.hasPrefix("#"), !source.hasPrefix(";") else { return nil }
        let negated = source.hasPrefix("!")
        let directoryOnly = source.hasSuffix("/")
        var isAnchored: Bool = false

        if source.hasPrefix("!") {
            source.removeFirst()
            source = source.trimmingCharacters(in: .whitespaces)
        }
        if source.hasPrefix("\\!") { source.removeFirst() }
        while source.hasSuffix("/") {
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

        var expression = GlobMatcher.expression(for: source)
        if isAnchored && !source.hasSuffix("/**") { expression += "(?:/.*)?" }
        expression = "^" + expression + "$"
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: expression
        ) else {
            return nil
        }
        return Pattern(
            expression: regex, isAnchored: isAnchored, raw: mask, negated: negated,
            directoryOnly: directoryOnly)
    }

    /// Build the regular expression of a mask.
    ///
    /// - Parameters:
    ///   - mask: The mask.
    ///   - anchored: Whether the mask is relative to the root.
    /// - Returns: The regular expression.
    private static func expression(for mask: String) -> String {
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
                    index = afterStars
                    continue
                }
                result += "[^/]*"
            } else if character == "?" {
                result += "[^/]"
            } else if character == "\\", mask.index(after: index) < mask.endIndex {
                index = mask.index(after: index)
                result += NSRegularExpression.escapedPattern(for: String(mask[index]))
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = mask.index(after: index)
        }

        return result
    }
}

private extension NSRegularExpression {
    func matches(_ value: String) -> Bool {
        firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
